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
		hooks = {
			block-envrc = ''
				#!/usr/bin/env bash
				# Best-effort guardrail against reading .envrc (which commonly holds
				# secrets) via the *Bash* tool.
				# NOTE: this is a guardrail, not a security boundary. The agent runs
				# as the same (rootless) user that owns .envrc, so a determined
				# process can still read it (e.g. by constructing the filename at
				# runtime inside an interpreter). The only real fix is to not
				# materialize the secret in a file the user can read.
				input=$(cat)
				tool_name=$(jq -r '.tool_name // empty' <<<"$input")

				deny() {
					jq -n --arg reason "$1" '{hookSpecificOutput: {hookEventName: "PreToolUse", permissionDecision: "deny", permissionDecisionReason: $reason}}'
					exit 0
				}

				# True if the string, treated as a path/glob, targets .envrc: the
				# literal name (.envrc, .envrc.local, ...) or a glob that could
				# expand to it (.env*, .envr?, .env?c, .envr[c], ...).
				targets_envrc() {
					grep -qiE '\.envrc([^a-z0-9]|$)|\.env[a-z0-9]*[*?[]' <<<"$1"
				}

				case "$tool_name" in
					Bash)
						command=$(jq -r '.tool_input.command // empty' <<<"$input")
						if [[ -n "$command" ]]; then
							# Collapse the common obfuscations (quotes, backslashes) so
							# spellings like .env"r"c, split-quote forms, and .env\rc all
							# normalize back to .envrc before matching.
							norm=''${command//\"/}
							norm=''${norm//\'/}
							norm=''${norm//\\/}
							# Block ANY reference to .envrc, not just known readers: cp/mv/
							# ln, source/., find -exec, dd, base64 and even `f=.envrc`
							# assignments all name the file and are caught here.
							if targets_envrc "$norm"; then
								deny "Referencing .envrc in a shell command is blocked (may contain secrets)."
							fi
						fi
						;;
				esac

				exit 0
			'';
		};
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
			sandbox = {
				enable = true;
			};
			env = {
				CLAUDE_CODE_ENABLE_AUTO_MODE = "1";
			};
			# Block the Read and Grep tools from touching .envrc at the harness
			# permission layer (enforced in-process, no hook needed).
			permissions = {
				deny = [
					"Read(.envrc)"
					"Read(**/.envrc)"
					"Read(//**/.envrc)"
					"Grep(.envrc)"
					"Grep(**/.envrc)"
					"Grep(//**/.envrc)"
				];
			};
			hooks = {
				PreToolUse = [
					{
						matcher = "Bash";
						hooks = [
							{
								type = "command";
								command = "${config.home.homeDirectory}/.claude/hooks/block-envrc";
							}
						];
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
