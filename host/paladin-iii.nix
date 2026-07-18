# For Framework 13 (for Chromebook and 7040 boards)
{ lib, age-secrets, lanzaboote, nixos-hardware, ... }: {
	imports = [ 
		# Laptop hardware
		# Semi-portable configs
		lanzaboote.nixosModules.lanzaboote
		nixos-hardware.nixosModules.framework-13-7040-amd
		
		./hardware-aspect/mainboard-7040.nix
		./hardware-aspect/disk.nix
		./hardware-aspect/measured-boot.nix
		./hardware-aspect/kensington-infinity-dock.nix
		./hardware-aspect/printer.nix
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
		};
		initrd = {
			availableKernelModules = [ 
				"nvme" 					# For disk
				"thunderbolt" 	# For dock
				"xhci_pci" 			# For USB (but doesn't work?)
				"usb_storage" 
				"sd_mod" 
			];
			secrets."/var/lib/measured-boot/fido2-fde-salt.luks" =
				"/run/agenix/paladin-iii/measured-boot/fido2-fde-salt.luks";
		};
		kernelParams = [
			"quiet"
		];
	};

	networking.hostName = "paladin-iii";
	networking.hostId = "cafebabe";

	# Peripherals
  hardware.hackrf.enable = true;
	hardware.wooting.enable = true; # This requires unfree license

	# Root secrets (decrypts to `/run/agenix/*`)
  age.secrets."paladin-iii/secure-boot/GUID".file = age-secrets.paladin-iii.secure-boot.GUID;
  age.secrets."paladin-iii/secure-boot/keys/PK/PK.key".file = age-secrets.paladin-iii.secure-boot.keys.PK."PK.key";
  age.secrets."paladin-iii/secure-boot/keys/PK/PK.pem".file = age-secrets.paladin-iii.secure-boot.keys.PK."PK.pem";
  age.secrets."paladin-iii/secure-boot/keys/KEK/KEK.key".file = age-secrets.paladin-iii.secure-boot.keys.KEK."KEK.key";
  age.secrets."paladin-iii/secure-boot/keys/KEK/KEK.pem".file = age-secrets.paladin-iii.secure-boot.keys.KEK."KEK.pem";
  age.secrets."paladin-iii/secure-boot/keys/db/db.key".file = age-secrets.paladin-iii.secure-boot.keys.db."db.key";
  age.secrets."paladin-iii/secure-boot/keys/db/db.pem".file = age-secrets.paladin-iii.secure-boot.keys.db."db.pem";
  age.secrets."paladin-iii/measured-boot/fido2-fde-salt.luks".file = age-secrets.paladin-iii.measured-boot."fido2-fde-salt.luks";

  age.secrets."paladin-iii/machine-id" = {
    file = age-secrets.paladin-iii.machine-id;
    mode = "0444";   # machine-id must be world-readable (dbus, user sessions, NM)
  };

  # Regular file at the canonical path, ordered after agenix decryption
  system.activationScripts.machineId = {
    deps = [ "agenix" ];
    text = ''
      install -m 0444 /run/agenix/paladin-iii/machine-id /etc/machine-id
    '';
  };

	age.secrets."paladin-iii/hashed-password".file = age-secrets.paladin-iii.hashed-password;

	# Consumed by ensure-printers (hardware/peripherals/printer.nix)
	age.secrets."network/malone-360-printer-uri".file = age-secrets.network.malone-360-printer-uri;
}
