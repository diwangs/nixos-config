# Home packages and programs shared between the laptop and rootless devboxes
# (imported by package/home-manager.nix and system/home-manager.devbox.nix).
# Keep this list headless: no desktop, dconf, Flatpak, or system-service
# assumptions — and no laptop-only specialArgs (`secrets`, `pkgs-stable`).
{ config, pkgs, lib, ... }: {
	home.packages = with pkgs; [
		# Runtime environment (or environment manager)
		fnm										# Node.js version manager 					(eval $(fnm env))
		uv										# Python environment manager

		# Little tools
		jq										# JSON parser

		# Claude Code sandboxed Bash tool (Linux): bubblewrap enforces the
		# filesystem/network boundary, socat relays traffic through the proxy.
		# The optional seccomp helper (@anthropic-ai/sandbox-runtime, npm-global)
		# is intentionally skipped: without it Unix-socket blocking is absent,
		# which keeps ssh-agent reachable for `git push` from sandboxed Bash.
		bubblewrap
		socat
	];

	# Dev
	programs.direnv = {
		enable = true; # Add direnv package and sets the shell hook
		nix-direnv.enable = true; # Cached nix-shell/nix develop environments
	};
	programs.gh.enable = true;

	# CLI-based agent: Claude Code
	# NOTE: `settings` is intentionally left empty. home-manager writes
	# settings.json as a read-only /nix/store symlink, which makes Claude Code's
	# own runtime writes (e.g. adjusting the effort level) fail with EROFS. We
	# instead materialize a writable copy in the activation script below.
	programs.claude-code = {
		enable = true;
		settings = { };
	};

	# Copy settings.json into place as a real, writable file so Claude Code can
	# persist runtime changes (effort level, etc.). Runs unconditionally on
	# every switch and every boot, so any runtime edits are reset to these
	# declarative defaults on the next activation.
	home.activation.claudeSettings = lib.hm.dag.entryAfter [ "linkGeneration" ] ''
		dst="$HOME/.claude/settings.json"
		run rm -f "$dst"
		run install -Dm600 ${(pkgs.formats.json { }).generate "claude-code-settings.json" {
			"$schema" = "https://json.schemastore.org/claude-code-settings.json";
			defaultMode = "auto";
			tui = "default"; # Prevent spammy ctrl+g
			env = {
				CLAUDE_CODE_ENABLE_AUTO_MODE = "1";
			};
			# OS-level (bubblewrap) sandbox for the Bash tool. Writes are confined
			# to the working directory + session $TMPDIR by default; reads default
			# to the whole filesystem, so sensitive paths are denied explicitly
			# below. Bash commands that need out-of-repo access fail in-sandbox and
			# escalate to a normal permission prompt (the "ask" fallback).
			sandbox = {
				enabled = true;             # NB: real schema key is `enabled`, not `enable`.
				failIfUnavailable = true;   # Never silently run unsandboxed (incl. devboxes).
				network = {
					allowedDomains = [ "*" ];   # Unrestricted network, no per-domain prompts.
					allowLocalBinding = true;   # Let dev servers bind localhost inside the sandbox.
				};
				# Block reads of credential material from sandboxed Bash. `deny`
				# denies file reads and unsets matching env vars per command.
				credentials.files = [
					{ path = "~/.ssh"; mode = "deny"; }
					{ path = "~/.aws"; mode = "deny"; }
					{ path = "~/.gnupg"; mode = "deny"; }
					{ path = "~/.claude/.credentials.json"; mode = "deny"; } # Claude Code OAuth token
				];
				# Absolute secret paths (native sandbox syntax: `/` = filesystem root).
				# If the agenix home-manager module is ever adopted, its secrets land
				# in $XDG_RUNTIME_DIR/agenix (/run/user/<uid>/agenix) — add that here.
				filesystem.denyRead = [
					"/nix/secret"   # agenix host key
					"/run/agenix"   # decrypted agenix secrets (system module)
				];
			};
		}} "$dst"
	'';

	# CLI-based agent: Codex
	programs.codex = {
		enable = true;
		settings = { }; # Intentionally empty to allow mutability (e.g., dir trust)
	};

	# Copy config.toml into place as a real, writable file so Codex can persist
	# runtime changes (trusted directories, etc.). Runs unconditionally on every
	# switch and every boot, so any runtime edits are reset to these declarative
	# defaults on the next activation.
	home.activation.codexSettings = lib.hm.dag.entryAfter [ "linkGeneration" ] ''
		dst="$HOME/.codex/config.toml"
		run rm -f "$dst"
		run install -Dm600 ${(pkgs.formats.toml { }).generate "codex-config.toml" {
			model_provider = "amazon-bedrock";
		}} "$dst"
	'';
}
