# {
{ config, pkgs, lib, ... }: {
	# Enable the GNOME DM and DE.
	services.displayManager.gdm.enable = true;
	services.desktopManager.gnome.enable = true;
	
	# For Chromium-based program to use Wayland natively instead of XWayland
	# NOTE: this cause bugs, but so far it's bearable
	# 	- Spotify: no title bar, crashes if hover on title for too long
	environment.sessionVariables.NIXOS_OZONE_WL = "1";

	# Enable the X11 windowing system.
	# services.xserver.enable = true;
	services.gvfs.enable = true;
	services.udev.packages = [ pkgs.gnome-settings-daemon ];

	# Fonts: nerd-fonts
	fonts.packages = builtins.filter lib.attrsets.isDerivation (builtins.attrValues pkgs.nerd-fonts);

	# Nautilus video properties
	# https://github.com/NixOS/nixpkgs/issues/195936
	environment.sessionVariables.GST_PLUGIN_SYSTEM_PATH_1_0 = lib.makeSearchPathOutput "lib" "lib/gstreamer-1.0" (with pkgs.gst_all_1; [
		gst-plugins-good
		gst-plugins-bad
		gst-plugins-ugly
		gst-libav
	]);
}

