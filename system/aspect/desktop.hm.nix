{ config, pkgs, lib, ... }: {
	# Desktop
	dconf = {
		enable = true;
		settings = {
			"org/gnome/desktop/wm/preferences" = {
				# Enable minimize and maximize button
				button-layout = "appmenu:minimize,maximize,close";
			};
			"org/gnome/desktop/peripherals/mouse" = {
				# Flat (1:1) pointer accel. Originally added so ydotool's coordinate
				# injection landed accurately for Computer Use; kept as a general
				# preference now that the ydotool stack is removed.
				accel-profile = "flat";
			};
			"org/gnome/desktop/interface" = {
				# Activate the AT-SPI toolkit without actual tool (e.g., dictation)
				toolkit-accessibility = true;
			};
			"org/gnome/shell" = {
				app-picker-layout = [];	# Sort menu alphabetically
				# Find the name with `dconf watch /` and dragging and dropping
				favorite-apps = [
					"org.gnome.Nautilus.desktop"	# Files
					# "com.mitchellh.ghostty.desktop"
					"org.gnome.Console.desktop"
					"code.desktop"
					"claude-desktop.desktop"	# official Anthropic .desktop id
					"md.obsidian.Obsidian.desktop"
					"app.zen_browser.zen.desktop"
					"com.bitwarden.desktop.desktop"
					"com.yubico.yubioath.desktop"
					"com.spotify.Client.desktop"
				];
				# Pin extensions declaratively so a Shell restart can't silently
				# re-gate them via disable-user-extensions (GNOME flips this to true
				# after an unclean Shell restart, which is what hid Vitals).
				disable-user-extensions = false;
				enabled-extensions = with pkgs.gnomeExtensions; [
					vitals.extensionUuid
				];
			};
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