{ config, pkgs, lib, ... }: {
	# Desktop
	dconf.enable = true;
	dconf.settings = {
		"org/gnome/desktop/wm/preferences" = {
			# Enable minimize and maximize button
			button-layout = "appmenu:minimize,maximize,close";
		};
		"org/gnome/shell" = {
			app-picker-layout = [];	# Sort menu alphabetically
			# Find the name with `dconf watch /` and dragging and dropping
			favorite-apps = [
				"org.gnome.Nautilus.desktop"	# Files
				"com.mitchellh.ghostty.desktop"
				"code.desktop"
				"md.obsidian.Obsidian.desktop"
				"app.zen_browser.zen.desktop"
				"com.bitwarden.desktop.desktop"
				"com.yubico.yubioath.desktop"
				"com.spotify.Client.desktop"
			];
			# disable-user-extensions = false;
			# enabled-extensions = with pkgs.gnomeExtensions; [
			# 	vitals.extensionUuid
			# ];
		};
	};

	# Shell
	programs.zsh = {
		enable = true;	# required by home-manager `gpg-agent` to expose SSH keys
		historySubstringSearch.enable = true; # The only feature I need from OMZ
	};
	programs.starship = {		# Prompt theming
		enable = true;
		enableZshIntegration = true;
		# No settings, just use the `pure` shell
	};
}