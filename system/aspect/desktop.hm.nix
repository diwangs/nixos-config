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
					"org.gnome.Console.desktop"
					"code.desktop"
					"t3code.desktop"
					# "claude-desktop.desktop"	# official Anthropic .desktop id
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
				enabled-extensions = (with pkgs.gnomeExtensions; [
					vitals.extensionUuid
				]) ++ [
					# cua-driver Wayland helper; packaged in package/nixos.nix
					"winrects@cua"
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

	# Nautilus video properties (https://github.com/NixOS/nixpkgs/issues/195936):
	# This is set per-user via systemd.user.sessionVariables instead of 
	# environment.sessionVariables -> /etc/pam/environment to avoid colon-joining
	# onto GIO_EXTRA_MODULES in the GNOME session, breaking GIO module loading.
	systemd.user.sessionVariables.GST_PLUGIN_SYSTEM_PATH_1_0 =
		lib.makeSearchPathOutput "lib" "lib/gstreamer-1.0" (with pkgs.gst_all_1; [
			gst-plugins-good
			gst-plugins-bad
			gst-plugins-ugly
			gst-libav
		]);
}