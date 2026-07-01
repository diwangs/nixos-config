# {
{ config, pkgs, lib, ... }: {
	# Enable the GNOME DM and DE.
	services.displayManager.gdm.enable = true;
	services.desktopManager.gnome.enable = true;
	
	# For Chromium-based program to use Wayland natively instead of XWayland
	# NOTE: this cause bugs, but so far it's bearable
	environment.sessionVariables.NIXOS_OZONE_WL = "1";
	environment.sessionVariables.EDITOR = "code-wait"; # For Claude

	# Enable the X11 windowing system.
	# services.xserver.enable = true;
	services.gvfs.enable = true;
	services.udev.packages = [ pkgs.gnome-settings-daemon ];

	# NOTE: the ydotool stack (programs.ydotool + YDOTOOL_SOCKET, and the `ydotool`
	# group in aspect/users.nix) was removed in the migration to the official
	# Claude Desktop — it existed only for Computer Use input injection, which the
	# official Linux beta reports as unsupported_platform.

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

