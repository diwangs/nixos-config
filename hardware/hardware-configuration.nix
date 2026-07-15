# For Framework 13 (for Chromebook and 7040 boards)
{ config, lib, pkgs, secrets, ... }: {
	imports = [ 
		# Laptop hardware
		./mainboard-7040.nix
		# ./mainboard-chromebook.nix
		./disk.nix
		# ./qualcomm-ncm865.nix

		# Peripherals
		./peripherals/kensington-infinity-dock.nix
		./peripherals/printer.nix
		# ./peripherals/udev-rules/hackrf-one.nix
		# ./peripherals/udev-rules/wooting.nix
		# ./peripherals/egpu.nix # My setup changes, so we don't need egpu anymore
	];

	# Enable non-free firmware (Qualcomm NCM865, Radeon, NPU, etc.)
	# This is defined in `not-detected.nix`, but let's define explicitly
	hardware.enableRedistributableFirmware = lib.mkDefault true;

	# Sensors for auto-brightness
	hardware.sensor.iio.enable = true;

	# Framework Laptop are x86-only (for now...)
	nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";

	# Lanzaboote replaces the systemd-boot module and signs the boot chain.
	boot.loader.systemd-boot.enable = lib.mkForce false;
	boot.lanzaboote = {
		enable = true;
		pkiBundle = "/run/agenix/paladin-iii/secureboot";
		configurationLimit = 5;		# Each initrd is ~62MB; 10 generations overflows 512MiB ESP
		autoGenerateKeys.enable = false;	# We use agenix
		autoEnrollKeys = {
			enable = true;
			autoReboot = false;
			includeMicrosoftKeys = true;
			includeFirmwareBuiltinKeys = true;
		};
	};
	boot.loader.timeout = 0;	# could still select by tapping arrow keys

	# initrd
	boot.initrd.availableKernelModules = [ 
		"nvme" 					# For disk
		"thunderbolt" 	# For dock
		"xhci_pci" 			# For USB (but doesn't work?)
		"usb_storage" 
		"sd_mod" 
	];
	boot.initrd.kernelModules = [ ];

	# Kernel
	boot.kernelParams = [
		"quiet"
	];
	boot.extraModulePackages = [ ];

	networking.hostName = "paladin-iii";
	networking.hostId = "cafebabe";

	# Peripherals
  hardware.hackrf.enable = true;
	hardware.wooting.enable = true; # This requires unfree license
}
