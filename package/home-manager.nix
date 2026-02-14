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

{ config, pkgs, pkgs-stable, secrets,  ... }: rec {
	home.packages = with pkgs; [
		# System
		lm_sensors						# Power and temperature monitoring
		helvum								# Pipewire multimedia patchbay
		yubioath-flutter			# Yubikey reader

		# Runtime environment (or environment manager)
		fnm										# Node.js version manager 					(eval $(fnm env))
		conda									# Python distribution	  						(conda-shell)
		github-copilot-cli 		# Agentic LLM in the CLI

		# Media
		vlc

		# Peripherals
		# sdrangel					# SDR, failed on current version of flake?
		# mbelib						# sdrangel: decode AMBe (e.g., C4FM, D-STAR, DMR)
		wsjtx									# FT8 and WSPR
		flrig									# Radio remote control (part of fldigi)
		trezor-suite					# Trezor wallet (since no WebUSB in Firefox)
	] ++ [
		pkgs-stable.codeql 		# Pin CodeQL. Also prevents download from vscode plugin
	];

	# Dev
	programs.direnv.enable = true; # Add direnv package and sets the shell hook
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
	# programs.claude-code.enable = true;

	# IDE
	programs.vscode = {
		enable = true;
		mutableExtensionsDir = false;
		profiles.default = {
			enableUpdateCheck = false;
			enableExtensionUpdateCheck = false;
			extensions = with pkgs.vscode-extensions; [
				# DevEx
				mkhl.direnv
				ms-vscode-remote.remote-ssh		# Unfree
				
				# Language support
				bbenoist.nix
				redhat.ansible
				redhat.vscode-yaml
				ms-python.python
				ms-python.vscode-pylance			# Unfree

				# Jupyter
				ms-toolsai.jupyter
				ms-toolsai.jupyter-renderers
				ms-toolsai.jupyter-keymap
				ms-toolsai.vscode-jupyter-cell-tags
				ms-toolsai.vscode-jupyter-slideshow
			] ++ (with pkgs.nix-vscode-extensions.vscode-marketplace-release; [
				github.copilot-chat						# Unfree
				github.vscode-codeql					# Unfree
			]);
			userSettings = {
				"editor.tabSize" = 2;
				"editor.minimap.enabled" = false;
				"extensions.autoUpdate" = false;
				"terminal.integrated.defaultProfile.linux" = "zsh";

				# Extensions
				"redhat.telemetry.enabled" = false;
				"direnv.restart.automatic" = true;

				# CodeQL plugin
				"codeQL.githubDatabase.download" = "never";
				"codeQL.runningQueries.memory" = 8192;

				# Copilot
				"chat.commandCenter.enabled" = false;
				"window.commandCenter" = false;
				# "chat.extensionUnification.enabled" = false;
				"editor.inlineSuggest.enabled" = false; # Trigger with Alt + \
				# Modify with `editor.inlineSuggest.trigger`
				"github.copilot.nextEditSuggestions.enabled" = false; # Red and green boxes

				# "sonarlint.pathToNodeExecutable" = "/etc/profiles/per-user/diwangs/bin/node";
			};
		};
	};
}
