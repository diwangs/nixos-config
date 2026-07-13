# Home packages and programs shared between the laptop and rootless devboxes
# (imported by package/home-manager.nix and system/home-manager.devbox.nix).
# Keep this list headless: no desktop, dconf, Flatpak, or system-service
# assumptions — and no laptop-only specialArgs (`secrets`, `pkgs-stable`).
{ config, pkgs, lib, ... }:
{
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

		# Sweeps the empty stub files/dirs/char-devices that bubblewrap leaves
		# behind in the sandboxed working directory when it deny-mounts /dev/null
		# over a path that doesn't exist yet (upstream: anthropics/claude-code#17087,
		# anthropic-experimental/sandbox-runtime#139 — reopened after a partial fix,
		# still unresolved for non-graceful command termination as of 2026-07).
		# Matched by exact name *and* emptiness, so a file that ever gains real
		# content (e.g. an actual package.json) is never touched.
		#
		# Anthropic's own in-process cleanup (sandbox-runtime's cleanupAfterCommand,
		# confirmed by decompiling the shipped bun-compiled binary) assumes the bind
		# mount is already torn down by the time it runs and never calls `umount` —
		# zero occurrences of that string in the whole binary. When the mount
		# outlives the command (orphaned/non-gracefully-killed bwrap, or a mount
		# that leaked into a longer-lived namespace) its own `rm`-equivalent hits
		# EBUSY, gets silently swallowed, and the path is never retried. So we
		# unmount first (plain, then lazy as a fallback for a still-referenced
		# mount) before ever touching the path, and every mutating step is
		# `|| true`-guarded so one busy/failed entry can't abort the rest of the
		# sweep under `set -e` the way a bare `rm -f` here once did.
		#
		# Materialized (as an executable file, not a settings.json entry) via
		# the `hooks` option so it lands at a stable path in ~/.claude/hooks/
		# that the hand-rolled settings.json below can reference by name.

		# NOTE: This still leaves 3 subdir inside of .claude, don't remove them.
		hooks."claude-clean-sandbox-debris" = ''
			#!${pkgs.bashInteractive}/bin/bash
			set -euo pipefail

			cwd="$(${pkgs.jq}/bin/jq -r '.cwd // empty')"
			[ -n "$cwd" ] && cd "$cwd" 2>/dev/null || exit 0

			junk=(
				.bashrc .bash_profile .zshrc .zprofile .profile .gitconfig .mcp.json
				.idea .vscode .github .ripgreprc scripts
				.env .env.local .env.development .env.development.local
				.env.test .env.test.local .env.production .env.production.local .envrc
				.npmrc .yarnrc .yarnrc.yml package.json package-lock.json
				pnpm-lock.yaml yarn.lock bunfig.toml .gitmodules
			)

			for name in "''${junk[@]}"; do
				${pkgs.util-linux}/bin/umount -- "$name" 2>/dev/null \
					|| ${pkgs.util-linux}/bin/umount -l -- "$name" 2>/dev/null \
					|| true
				[ -e "$name" ] || [ -L "$name" ] || continue
				if [ -c "$name" ]; then
					rm -f -- "$name" || true
				elif [ -f "$name" ] && [ ! -s "$name" ]; then
					rm -f -- "$name" || true
				elif [ -d "$name" ] && [ -z "$(ls -A "$name" 2>/dev/null)" ]; then
					rmdir -- "$name" 2>/dev/null || true
				fi
			done

			if [ -d node_modules ]; then
				find node_modules -depth -type f -empty -delete 2>/dev/null || true
				find node_modules -depth -type d -empty -delete 2>/dev/null || true
			fi

			exit 0
		'';
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
				CLAUDE_CODE_SUBPROCESS_ENV_SCRUB = "1";
				SHELL = "${pkgs.bashInteractive}/bin/bash";
				CLAUDE_CODE_SHELL = "${pkgs.bashInteractive}/bin/bash";
				CLAUDE_BASH_NO_LOGIN = "1";
			};
			# OS-level (bubblewrap) sandbox for the Bash tool. Writes are confined
			# to the working directory + session $TMPDIR by default; reads default
			# to the whole filesystem, so sensitive paths are denied explicitly
			# below. Bash commands that need out-of-repo access fail in-sandbox and
			# escalate to a normal permission prompt (the "ask" fallback).
			sandbox = {
				enabled = true;             # NB: real schema key is `enabled`, not `enable`.
				failIfUnavailable = true;   # Never silently run unsandboxed (incl. devboxes).
				allowUnsandboxedCommands = false;	# Disallow fallback
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
					"/run/agenix.d"   # decrypted agenix secrets (system module)
				];
				# Re-allow commondir because it breaks git operation on main branch
				filesystem.allowRead = [ "**/.git/commondir" ];
			};
			# Sweep bwrap's leftover deny-mount stub files after every sandboxed
			# Bash call (the common case) and again at session start (catches
			# whatever a non-gracefully-terminated previous session left behind,
			# since its mount namespace is already gone by then — see the
			# claude-clean-sandbox-debris hook above for the upstream bug refs).
			hooks = {
				PostToolUse = [
					{
						matcher = "Bash";
						hooks = [{ type = "command"; command = "${config.programs.claude-code.configDir}/hooks/claude-clean-sandbox-debris"; }];
					}
				];
				SessionStart = [
					{
						hooks = [{ type = "command"; command = "${config.programs.claude-code.configDir}/hooks/claude-clean-sandbox-debris"; }];
					}
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
