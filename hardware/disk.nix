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
	};

	# Reset root subvolume every boot (replaces postOpenCommands for systemd stage 1)
	boot.initrd.systemd.services."reset-root" = {
		description = "Reset btrfs root subvolume to clean snapshot";
		wantedBy = [ "cryptsetup.target" ];
		after = [ "cryptsetup.target" ];
		before = [ "sysroot.mount" ];
		unitConfig.DefaultDependencies = "no";
		serviceConfig.Type = "oneshot";
		script = ''
			mkdir -p /mnt
			mount /dev/mapper/decrypted_root /mnt
			btrfs subv show /mnt/@rw > /dev/null 2>&1 && btrfs subv delete -Rc /mnt/@rw || true
			btrfs subv snapshot /mnt/@snapshots/@ /mnt/@rw
			umount /mnt
		'';
	};

	# Prevents systemd from creating subvolumes: adds them to 00-nixos.conf
	systemd.tmpfiles.rules = [
		"d /srv                0755 root root -"
		"d /tmp                1777 root root 10d"
		"d /var/tmp            1777 root root 30d"
		"d /var/lib/machines   0700 root root -"
		"d /var/lib/portables  0700 root root -"
	];

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