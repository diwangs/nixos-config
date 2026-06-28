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

	# Claude Desktop Computer Use needs ydotool's uinput daemon for mouse/keyboard
	# input on Wayland (xdotool can't inject events into Wayland compositors). This
	# runs the hardened ydotoold service, creates the `ydotool` group (membership
	# set in aspect/users.nix), and grants /dev/uinput.
	programs.ydotool.enable = true;

	# The ydotool module only exports YDOTOOL_SOCKET via environment.variables,
	# which lands in /etc/set-environment (login SHELLS only). GNOME/GDM-launched
	# GUI apps don't source that, so Claude Desktop couldn't find ydotoold and its
	# clicks hung with `spawnSync /bin/sh ETIMEDOUT`. Re-export it through
	# sessionVariables -> /etc/pam/environment, the same PAM channel that already
	# delivers NIXOS_OZONE_WL to graphical sessions. The literal path matches the
	# module's RuntimeDirectory ("ydotoold") + socket-path; it's hardcoded there,
	# and we can't reference config.environment.variables here (sessionVariables is
	# merged into it, so that would be infinite recursion).
	environment.sessionVariables.YDOTOOL_SOCKET = "/run/ydotoold/socket";

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

