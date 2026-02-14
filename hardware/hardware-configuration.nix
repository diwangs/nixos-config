# For Framework 13 (for Chromebook and 7040 boards)
{ config, lib, pkgs, secrets, ... }: {
	imports = [ 
		# Laptop hardware
		./mainboard-7040.nix
		# ./mainboard-chromebook.nix
		./disk.nix
		# ./qualcomm-ncm865.nix

		# Peripherals
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

	# Use the systemd-boot EFI boot loader.
	boot.loader.systemd-boot = {
		enable = true;
		configurationLimit = 10;	# We only have 512MiB of ESP
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

		# Avoid generating machine-id every boot 
		# This is used for NetworkManager IPv6 DUID
		"systemd.machine_id=${secrets.paladin-iii.machine-id}"
		# "amdgpu.dcdebugmask=0x10"
	];
	boot.extraModulePackages = [ ];

	networking.hostId = secrets.paladin-iii.host-id;
	networking.hostName = "paladin-iii";

	# Peripherals
  hardware.hackrf.enable = true;
	hardware.wooting.enable = true; # This requires unfree license
}
