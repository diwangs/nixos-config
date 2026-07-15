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

		# Minimal rm-only sweep of the mount-point files bwrap leaves on the real
		# working dir when it deny-binds a path that doesn't exist yet. The bwrap
		# shim (../overlay/claude-code.nix) now contains the *mounts*
		# in a private-propagation namespace so they no longer leak and stick as
		# unremovable char-devices — but the mount-point *files* themselves are
		# writes through the rw cwd bind and persist on disk. No umount needed
		# anymore (nothing stays mounted), no worktreeConfig handling.
		#
		# The general list is matched by exact name *and* emptiness, so a file
		# that ever gains real content (e.g. an actual package.json) is never
		# touched. `.git/commondir` is special-cased: in a main worktree (`.git`
		# is a directory) git resolves the common dir to `.git` itself and a
		# `commondir` file must NOT exist — any leftover (empty from the shim's
		# bind, or a stray "." from an earlier run) makes libgit2/nixos-rebuild
		# reject the repo — so remove it regardless of content. Linked worktrees
		# have a `.git` *file*, not a directory, so this never touches theirs.
		hooks."claude-clean-sandbox-debris" = ''
#!${pkgs.runtimeShell}
set -eu

cwd="$(${pkgs.jq}/bin/jq -r '.cwd // empty')"
[ -n "$cwd" ] && cd "$cwd" 2>/dev/null || exit 0

for name in .zshrc .zprofile; do
	path="$HOME/$name"
	if [ -L "$path" ] || { [ -f "$path" ] && [ ! -s "$path" ]; }; then
		rm -f -- "$path" || true
	fi
done

for name in \
	.bashrc .bash_profile .zshrc .zprofile .profile .gitconfig .mcp.json \
	.idea .vscode .github .ripgreprc scripts \
	.env .env.local .env.development .env.development.local \
	.env.test .env.test.local .env.production .env.production.local .envrc \
	.npmrc .yarnrc .yarnrc.yml package.json package-lock.json \
	pnpm-lock.yaml yarn.lock bunfig.toml .gitmodules; do
	[ -e "$name" ] || [ -L "$name" ] || continue
	if [ -c "$name" ]; then
		rm -f -- "$name" || true
	elif [ -f "$name" ] && [ ! -s "$name" ]; then
		rm -f -- "$name" || true
	elif [ -d "$name" ] && [ -z "$(ls -A "$name" 2>/dev/null)" ]; then
		rmdir -- "$name" 2>/dev/null || true
	fi
done

if [ -d .git ] && { [ -e .git/commondir ] || [ -L .git/commondir ]; } \
		&& [ ! -d .git/commondir ]; then
	rm -f -- .git/commondir || true
fi

# bwrap leaves an empty-file/dir skeleton under node_modules when it deny-binds
# nested paths there. Prune the empties bottom-up (files first, then the dirs
# they leave behind); a populated node_modules is untouched since -empty skips
# anything with real content.
if [ -d node_modules ]; then
	${pkgs.findutils}/bin/find node_modules -depth -type f -empty -delete 2>/dev/null || true
	${pkgs.findutils}/bin/find node_modules -depth -type d -empty -delete 2>/dev/null || true
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
		run install -Dm600 ${(pkgs.formats.json { }).generate "claude-code-settings.json" (
		let
			# Path where agents should not access
			secretGlobs = [
				"~/.ssh/**"
				"~/.aws/**"
				"~/.gnupg/**"
				"~/.claude/.credentials.json"   # Claude Code OAuth token
				"//nix/secret/**"               # agenix host key
				"//run/agenix.d/**"             # decrypted agenix secrets (nixos module)
				"//run/user/**"                 # decrypted agenix secrets (home-manager module)
			];
			# Tools to restrict: Grep and Glob follows Read, Write follows Edit
			secretTools = [ "Read" "Edit" ]; 
		in {
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
			permissions.deny =
				lib.concatMap (p: map (t: "${t}(${p})") secretTools) secretGlobs;
			# Bash tool restriction: sandboxing (restricting at the mount level)
			# - Write allowlist -> allow cwd, tmpdir, and a few /dev (null, etc.) + Edit permission
			# - Read denylist -> allow all + deny known creds path + Read permission
			sandbox = {
				enabled = true;             # NB: real schema key is `enabled`, not `enable`.
				failIfUnavailable = true;   # Never silently run unsandboxed (incl. devboxes).
				allowUnsandboxedCommands = false;	# Disallow fallback
				network = {
					allowedDomains = [ "*" ];   # Unrestricted network, no per-domain prompts.
					allowLocalBinding = true;   # Let dev servers bind localhost inside the sandbox.
					# allowAllUnixSockets = true; # Enable for nix-project only
				};
			};
			# Sweep bwrap's 0-byte deny-mount leftover files after every sandboxed
			# Bash call (the common case) and once at session start (belt-and-
			# suspenders for anything a crashed previous session left behind).
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
		})} "$dst"
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
			approval_policy = "on-request";
			model = "openai.gpt-5.6-terra";
			model_reasoning_effort = "xhigh";
		}} "$dst"
	'';
}
