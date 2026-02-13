{ config, pkgs, lib, ... }: {
	boot.kernelModules = [ 
		"vhci-hcd" 		# For usbip (client)
		"usbip_host"	# For usbip (server)
	];

  # Podman
	virtualisation = {
		containers = {
			enable = true;
			storage.settings = {
				storage = {
					driver = "overlay";
					runroot = "/run/containers/storage";
					graphroot = "/var/lib/containers/storage";
					rootless_storage_path = "/tmp/containers-$USER";
					options.overlay.mountopt = "nodev,metacopy=on";
				};
			};
		};
		oci-containers.backend = "podman";
		podman = {
			enable = true;
			dockerCompat = true;
			# For `docker-compose`
			defaultNetwork.settings.dns_enabled = true;
		};
	};
	environment.extraInit = ''
    if [ -z "$DOCKER_HOST" -a -n "$XDG_RUNTIME_DIR" ]; then
      export DOCKER_HOST="unix://$XDG_RUNTIME_DIR/podman/podman.sock"
    fi
  '';

	# List packages installed in system profile. To search, run:
	# $ nix search wget
	# System packages: packages that is run by the root user sans sudo
	# e.g. systemd units, gdm, etc.
	environment.systemPackages = with pkgs; [
		git         		# required for flakes

		# For firmware things
		fw-ectool     	# This is the same as tree's ectool
		dmidecode				# For updating too?

		# Container frontends
		podman-tui
		docker-compose
		distrobox

		# Gnome things
		gnomeExtensions.vitals	# Gnome performance manager
		ffmpegthumbnailer	# For video thumbnails
		ffmpeg-headless
		gdk-pixbuf				# For picutre thumbnails

		# Peripherals
		android-tools			# adb and friends
		config.boot.kernelPackages.usbip

		# Misc
		# brightnessctl		# Set brightness at boot
		iio-sensor-proxy	# For auto-brightness
		ntfs3g					# Open-source NTFS on FUSE (alt to kernel's NTFS3)
		hwloc
	];
}