{ config, pkgs, cua, ... }: let
	# cua-driver 0.7's GNOME Shell helper. Exposes org.cua.WinRects on the session
	# bus so cua-driver can read window frame rects (Mutter's only privileged
	# vantage point) and reconstruct GTK4 widget screen coords on Wayland, where
	# AT-SPI CoordType::Screen otherwise returns (0,0). Source is vendored in the
	# `cua` flake; metadata.json upstream caps at shell 47, so we widen it to cover
	# this box's GNOME 50 (its Gio/St/Clutter/Cairo APIs are stable across these).
	winrects-cua = pkgs.stdenv.mkDerivation {
		pname = "gnome-shell-extension-winrects-cua";
		version = "1";
		src = "${cua}/libs/cua-driver/wayland-helper/winrects@cua";
		nativeBuildInputs = [ pkgs.jq ];
		dontConfigure = true;
		dontBuild = true;
		installPhase = ''
			dir="$out/share/gnome-shell/extensions/winrects@cua"
			mkdir -p "$dir"
			cp extension.js "$dir/"
			jq '."shell-version" |= (. + ["48","49","50"] | unique)' \
				metadata.json > "$dir/metadata.json"
		'';
	};
in {
	boot.kernelModules = [
		"vhci-hcd" 		# For usbip (client)
		"usbip_host"	# For usbip (server)
	];

	environment.localBinInPath = true; # Include `~/.local/bin` e.g., for `uv`

	# List packages installed in system profile. To search, run:
	# $ nix search wget
	# System packages: packages that is run by the root user sans sudo
	# e.g. systemd units, gdm, etc.
	environment.systemPackages = with pkgs; [
		git         		# required for flakes

		# For firmware things
		fw-ectool     	# This is the same as tree's ectool
		dmidecode				# For updating too?
		sbctl						# Secure Boot status and verification

		# Container frontends
		podman-tui
		podman-compose
		# docker-compose
		distrobox

		# Gnome things
		gnomeExtensions.vitals	# Gnome performance manager
		winrects-cua			# cua-driver Wayland window-rect/cursor helper
		ffmpegthumbnailer	# For video thumbnails
		ffmpeg-headless
		gdk-pixbuf				# For picutre thumbnails
		libheif

		# Peripherals
		android-tools			# adb and friends
		config.boot.kernelPackages.usbip
		yubico-piv-tool		# Use lighter ykcs11 instead of opensc-pkcs11

		# Misc
		# brightnessctl		# Set brightness at boot
		iio-sensor-proxy	# For auto-brightness
		ntfs3g						# Open-source NTFS on FUSE (alt to kernel's NTFS3)
		hwloc
	];

	programs.yubikey-manager.enable = true;
}
