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
		./peripherals/yubikey.nix
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
	boot = {
		loader = {
			timeout = 0;	# Could still select by tapping arrow keys
			efi.canTouchEfiVariables = true;
			systemd-boot.enable = lib.mkForce false; # Use through lanzaboote instead
		};
		lanzaboote = {
			enable = true;
			pkiBundle = "/run/agenix/paladin-iii/secure-boot";
			configurationLimit = 5;		# Limit is 8. Each initrd is ~62MB;
			autoGenerateKeys.enable = false;	# Use through agenix instead
			autoEnrollKeys = {
				enable = true;
				autoReboot = false;
				includeMicrosoftKeys = true;
				includeFirmwareBuiltinKeys = true;
			};
			# Managed systemd-pcrlock policy to unlock `/dev/mapper/fido2-fde-salt`
			measuredBoot = {
				enable = true;
				pcrs = [ 
					0 		# platform-code (firmware version)
					4 		# boot-loader-code (lanzaboote stub)
					7 		# secure-boot-policy (PK, KEK, db, status)
				];
				# Define explicitly because of impermanence
				pcrlockDirectory = "/var/lib/pcrlock.d";
				pcrlockPolicy = "/var/lib/pcrlock.d/policy.json";
			};
		};
		initrd = {
			availableKernelModules = [ 
				"nvme" 					# For disk
				"thunderbolt" 	# For dock
				"xhci_pci" 			# For USB (but doesn't work?)
				"usb_storage" 
				"sd_mod" 
			];
		};
		kernelParams = [
			"quiet"
		];
	};

	# The upstream units only order themselves after var.mount. Ensure every
	# writer sees the nested persistent mount instead of the ephemeral root.
	systemd.services = lib.genAttrs [
		"systemd-pcrlock-firmware-code"
		"systemd-pcrlock-secureboot-policy"
		"systemd-pcrlock-secureboot-authority"
		"systemd-pcrlock-make-policy"
	] (_: {
		unitConfig.RequiresMountsFor = "/var/lib/pcrlock.d";
	});

	networking.hostName = "paladin-iii";
	networking.hostId = "cafebabe";

	# Peripherals
  hardware.hackrf.enable = true;
	hardware.wooting.enable = true; # This requires unfree license
}
