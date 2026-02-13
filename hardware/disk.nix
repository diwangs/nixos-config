{ config, lib, pkgs, secrets, ... }: 
let
	# Mount options that is applied to all mounts
  defaultMountOptions = [
		"relatime"		# Light access time recording
		"nodatasum"		# No checksuming since AEGIS already has signature
		"nodiscard"		# No TRIM
	];
in {
	# Add kernel module in initrd for decrypting AEAD
	boot.initrd.availableKernelModules = [ 
		"dm-integrity"
		"aegis128"
	];

	# Boot partition: EFI System Partition
	fileSystems."/boot" = { 
		device = "/dev/disk/by-uuid/${secrets.paladin-iii.boot-partition-uuid}";
		fsType = "vfat";
	};

	# Root partition: reset every boot
	fileSystems."/" = { 
		device = "/dev/disk/by-uuid/${secrets.paladin-iii.root-partition-uuid}";
		fsType = "btrfs";
		options = [ "subvol=@rw" ] ++ defaultMountOptions;
	};

	boot.initrd.luks.devices."decrypted_root" = { 
		device = "/dev/nvme0n1p2";
		bypassWorkqueues = true;
		postOpenCommands = ''
			mkdir /mnt
			mount /dev/mapper/decrypted_root /mnt
			rm -rf /mnt/@rw 2> /dev/null # This throws benign error about /var/lib/empty
			btrfs subv delete -C /mnt/@rw
			btrfs subv snapshot /mnt/@snapshots/@ /mnt/@rw
			umount /mnt
			rmdir /mnt
		'';
	};

	# States: persistent, snapshoted data
	fileSystems."/etc/nixos" = { 
		device = "/dev/disk/by-uuid/${secrets.paladin-iii.root-partition-uuid}";
		fsType = "btrfs";
		options = [ "subvol=states/@nixos" ] ++ defaultMountOptions;
	};

	fileSystems."/etc/NetworkManager/system-connections" = { 
		device = "/dev/disk/by-uuid/${secrets.paladin-iii.root-partition-uuid}";
		fsType = "btrfs";
		options = [ "subvol=states/@network" ] ++ defaultMountOptions;
	};

	fileSystems."/var/lib/bluetooth" = { 
		device = "/dev/disk/by-uuid/${secrets.paladin-iii.root-partition-uuid}";
		fsType = "btrfs";
		options = [ "subvol=states/@bluetooth" ] ++ defaultMountOptions;
	};

	fileSystems."/var/lib/boltd" = { 
		device = "/dev/disk/by-uuid/${secrets.paladin-iii.root-partition-uuid}";
		fsType = "btrfs";
		options = [ "subvol=states/@thunderbolt" ] ++ defaultMountOptions;
	};

	fileSystems."/home/diwangs" = { 
		device = "/dev/disk/by-uuid/${secrets.paladin-iii.root-partition-uuid}";
		fsType = "btrfs";
		options = [ "subvol=states/@home" ] ++ defaultMountOptions;
	};

	# Caches: persistent, non-snapshoted data
	fileSystems."/nix" = { 
		device = "/dev/disk/by-uuid/${secrets.paladin-iii.root-partition-uuid}";
		fsType = "btrfs";
		options = [ "subvol=caches/@nix" ] ++ defaultMountOptions;
	};

	fileSystems."/var/cache" = { 
		device = "/dev/disk/by-uuid/${secrets.paladin-iii.root-partition-uuid}";
		fsType = "btrfs";
		options = [ "subvol=caches/@varcache" ] ++ defaultMountOptions;
	};

	fileSystems."/home/diwangs/.cache" = { 
		device = "/dev/disk/by-uuid/${secrets.paladin-iii.root-partition-uuid}";
		fsType = "btrfs";
		options = [ "subvol=caches/@homecache" ] ++ defaultMountOptions;
	};

	fileSystems."/var/lib/flatpak" = { 
		device = "/dev/disk/by-uuid/${secrets.paladin-iii.root-partition-uuid}";
		fsType = "btrfs";
		options = [ "subvol=caches/@flatpak" ] ++ defaultMountOptions;
	};

	# Swap: same size as RAM (64 GiB), disables CoW
	fileSystems."/var/swap" = {
		device = "/dev/disk/by-uuid/${secrets.paladin-iii.root-partition-uuid}";
		fsType = "btrfs";
		options = [ "subvol=caches/@swap" "nodatacow" ] ++ defaultMountOptions;
	};

	swapDevices = [{
		device = "/var/swap/swapfile";
		size = 64 * 1024; # Accepts MiB
		# NOTE: Gnome system manager uses GB, not GiB
	}];
}