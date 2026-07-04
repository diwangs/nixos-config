# Home packages are user packages that lacks integrated synchronization 
# mechanism. User packages that have one (usually account-based), is 
# preferred to use flatpak instead. To achieve reproducibility, its data is 
# snapshoted.
# 
# Example of home packages: vscodium, starship, zsh, obs
# Example of flatpak packages: steam, brave browser
# 
# Few advantages of this approach:
# 1. Doesn't snapshot some authentication token
# 2. This kind of packages are usually closed-source, so we avoid unfree 
# 		packages in Nix
# 
# While this approach is not perfectly reproducible in hash sense
# it is reproducible in the synchronization sense, since the data are 
# snapshoted 

{ config, lib, pkgs, pkgs-stable, secrets, ... }: rec {
	home.packages = with pkgs; [
		# System
		lm_sensors						# Power and temperature monitoring
		crosspipe							# Pipewire multimedia patchbay

		# Runtime environment (or environment manager)
		fnm										# Node.js version manager 					(eval $(fnm env))
		# TODO: change `fnm` to `viteplus` when available to have similar workflow with `uv`
		uv										# Python environment manager
		conda									# Python environment manager	  		(conda-shell)
		ansible
		sshpass
		ansible-lint

		# Agentic
		claude-desktop
		# cua-driver: installed system-wide via services.cua-driver (nixos.nix)
		# github-copilot-cli 		# Agentic LLM in the CLI

		# Media
		vlc

		# Peripherals
		yubioath-flutter			# Yubikey reader
		trezor-suite					# Trezor wallet (since no WebUSB in Firefox)
		ledger-live-desktop
		wsjtx									# FT8 and WSPR
		flrig									# Radio remote control (part of fldigi)
		# sdrangel					# SDR, failed on current version of flake?
		# mbelib						# sdrangel: decode AMBe (e.g., C4FM, D-STAR, DMR)

		# Little tools
		jq										# JSON parser
	] ++ [
		pkgs-stable.codeql 		# Pin CodeQL. Also prevents download from vscode plugin
		# Small script to launch VSCode from Claude Code CLI
		(pkgs.writeShellScriptBin "code-wait" ''
			exec ${pkgs.vscode}/bin/code --wait "$@" \
				2> >(grep -v "is not in the list of known options, but still passed to Electron/Chromium" >&2)
		'')
	];
	
	# Dev
	programs.direnv.enable = true; # Add direnv package and sets the shell hook
	programs.gh.enable = true; # Add direnv package and sets the shell hook
	programs.java = { # Aside from installing jdk (latest LTS), this sets JAVA_HOME
		enable = true;
		package = pkgs.jdk25;							# Latest LTS
	};
	programs.git = {
		enable = true;
		lfs.enable = true;
		signing = {
			format = "openpgp";
			key = secrets.diwangs.gpg-git-sign-fingerprint; # S subkey fingerprint
		};
	};

	# IDE: VSCode official
	programs.vscode = {
		enable = true;
		mutableExtensionsDir = false;
		profiles.default = {
			enableUpdateCheck = false;
			enableExtensionUpdateCheck = false;
			keybindings = [
				{
					key = "ctrl+g"; # Conflicts with Claude Code CLI
					command = "-workbench.action.terminal.goToRecentDirectory";
					# Technically there's a when clause here, but we don't really need
					# the other one either.
				}
			];
			extensions = with pkgs.vscode-extensions; [
				# DevEx
				mkhl.direnv
				ms-vscode-remote.remote-ssh			# Unfree
				
				# Language support
				bbenoist.nix
				unifiedjs.vscode-mdx
				redhat.ansible
				redhat.vscode-yaml
				ms-python.python
				ms-python.vscode-python-envs
				# ms-python.vscode-pylance			# Unfree
				ms-pyright.pyright
				ms-azuretools.vscode-containers

				# Jupyter
				ms-toolsai.jupyter
				ms-toolsai.jupyter-renderers
				ms-toolsai.jupyter-keymap
				ms-toolsai.vscode-jupyter-cell-tags
				ms-toolsai.vscode-jupyter-slideshow

				# Agents
				anthropic.claude-code
			] ++ (with pkgs.nix-vscode-extensions.vscode-marketplace-release; [
				github.vscode-codeql					# Unfree
			]);
			userSettings = {
				"update.mode" = "none";
				"editor.tabSize" = 2;
				"editor.minimap.enabled" = false;
				"extensions.autoUpdate" = "off";
				"extensions.autoCheckUpdates" = false;
				"terminal.integrated.defaultProfile.linux" = "zsh";
				"redhat.telemetry.enabled" = false;

				# Copilot
				"window.commandCenter" = false;
				"editor.inlineSuggest.enabled" = false; # Trigger with Alt + \
				# Modify with `editor.inlineSuggest.trigger`
				# "chat.commandCenter.enabled" = false;
				"chat.viewSessions.orientation" = "stacked";
				# "github.copilot.nextEditSuggestions.enabled" = false; # Red and green boxes

				# Extension: direnv
				"direnv.restart.automatic" = false;

				# Extension: Claude Code
				"claudeCode.useTerminal" = true;
				"claudeCode.preferredLocation" = "panel";
				# "claudeCode.disableLoginPrompt" = true;

				# Extension: Container
				"containers.containerClient"= "com.microsoft.visualstudio.containers.podman";
				"containers.orchestratorClient"= "com.microsoft.visualstudio.orchestrators.podmancompose";

				# Extension: CodeQL
				"codeQL.githubDatabase.download" = "never";
				"codeQL.runningQueries.memory" = 8192;
			};
		};
	};

	# CLI-based agent: Claude Code through OpenRouter
	programs.claude-code = {
		enable = true;
		settings = {
			defaultMode = "auto";
			effortLevel = "xhigh";
			tui = "default"; # Prevent spammy ctrl+g
			env = {
				"ANTHROPIC_API_KEY" = ""; # Intentionally blank;
				"ANTHROPIC_AUTH_TOKEN" = secrets.diwangs.openrouter-token-personal;
				"ANTHROPIC_BASE_URL" = "https://openrouter.ai/api";
				# "CLAUDE_CODE_DISABLE_MOUSE_CLICKS" = "1";
				# Force 1M context for desktop-invoked Claude Code
				"CLAUDE_CODE_MAX_CONTEXT_TOKENS" = "1000000";
				"DISABLE_COMPACT" = "1";
			};
		};
	};

	programs.t3code = {
		enable = true;
	};

	# CLI-based agent: OpenCode
	programs.opencode = {
		enable = true;
		settings = {
			autoupdate = "notify";
		};
	};
}
