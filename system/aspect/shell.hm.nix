# Shell configuration shared between the laptop and rootless devboxes
# (imported by system/home-manager.devbox.nix, which the laptop entry also
# imports). Keep this file devbox-safe: no desktop, dconf, or NixOS-module
# assumptions.
{ config, pkgs, lib, ... }: {
	# Shell
	programs.zsh = {
		enable = true;	# required by home-manager `gpg-agent` to expose SSH keys
		# Pin the pre-XDG default explicitly; home-manager warns (and will flip
		# the default to $XDG_CONFIG_HOME/zsh) if left unset.
		dotDir = config.home.homeDirectory;
		historySubstringSearch.enable = true; # The only feature I need from OMZ
		autosuggestion.enable = true;
		enableCompletion = true;
		syntaxHighlighting.enable = true;
	};
	programs.starship = {		# Prompt theming
		enable = true;
		enableZshIntegration = true;
		# No settings, just use the `pure` shell
	};
}
