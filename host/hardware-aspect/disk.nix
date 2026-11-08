{ ... }:
let
  # Mount options that is applied to all mounts
  defaultMountOptions = [
    "relatime" # Light access time recording
    "nodatasum" # No checksuming since AEGIS already has signature
    "nodiscard" # No TRIM
  ];

  boot-partition-uuid = "02CE-E779";
  root-partition-uuid = "5f6d2a11-566c-42ed-ba66-4a5284b1636b";
in
{
  # Add kernel module in initrd for decrypting AEAD
  boot.initrd.availableKernelModules = [
    "dm-integrity"
    "aegis128"
  ];
  boot.initrd.systemd.tpm2.enable = true;

  # Boot partition: EFI System Partition
  fileSystems."/boot" = {
    device = "/dev/disk/by-uuid/${boot-partition-uuid}";
    fsType = "vfat";
  };

  # Root partition: reset every boot
  fileSystems."/" = {
    device = "/dev/disk/by-uuid/${root-partition-uuid}";
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

  # Persistent storage: each subvolume is mounted under /persist in initrd, and
  # impermanence bind-mounts it into place (see host/paladin-iii.nix). The
  # /persist parents live on the ephemeral root, so anything persisted must
  # have its own subvolume here: loose files under /persist are wiped.

  # States: persistent, snapshoted data
  fileSystems."/persist/states/etc/nixos" = {
    device = "/dev/disk/by-uuid/${root-partition-uuid}";
    fsType = "btrfs";
    options = [ "subvol=states/@nixos" ] ++ defaultMountOptions;
    neededForBoot = true;
  };

  fileSystems."/persist/states/etc/NetworkManager/system-connections" = {
    device = "/dev/disk/by-uuid/${root-partition-uuid}";
    fsType = "btrfs";
    options = [ "subvol=states/@network" ] ++ defaultMountOptions;
    neededForBoot = true;
  };

  fileSystems."/persist/states/var/lib/bluetooth" = {
    device = "/dev/disk/by-uuid/${root-partition-uuid}";
    fsType = "btrfs";
    options = [ "subvol=states/@bluetooth" ] ++ defaultMountOptions;
    neededForBoot = true;
  };

  fileSystems."/persist/states/var/lib/boltd" = {
    device = "/dev/disk/by-uuid/${root-partition-uuid}";
    fsType = "btrfs";
    options = [ "subvol=states/@thunderbolt" ] ++ defaultMountOptions;
    neededForBoot = true;
  };

  fileSystems."/persist/states/home/diwangs" = {
    device = "/dev/disk/by-uuid/${root-partition-uuid}";
    fsType = "btrfs";
    options = [ "subvol=states/@home" ] ++ defaultMountOptions;
    neededForBoot = true;
  };

  # Backing mount is in initrd, but impermanence bind-mounts /var/lib/systemd
  # only in stage 2 (before local-fs.target). random-seed and pcrlock wait for
  # it via RequiresMountsFor (see measured-boot.nix for the pcrlock units).
  fileSystems."/persist/states/var/lib/systemd" = {
    device = "/dev/disk/by-uuid/${root-partition-uuid}";
    fsType = "btrfs";
    options = [ "subvol=states/@systemd" ] ++ defaultMountOptions;
    neededForBoot = true;
  };

  # Mounted directly: the store must exist before any bind mount
  fileSystems."/nix" = {
    device = "/dev/disk/by-uuid/${root-partition-uuid}";
    fsType = "btrfs";
    options = [ "subvol=caches/@nix" ] ++ defaultMountOptions;
  };

  # Caches: persistent, non-snapshoted data
  fileSystems."/persist/caches/var/log" = {
    device = "/dev/disk/by-uuid/${root-partition-uuid}";
    fsType = "btrfs";
    options = [ "subvol=caches/@log" ] ++ defaultMountOptions;
    neededForBoot = true;
  };

  fileSystems."/persist/caches/var/cache" = {
    device = "/dev/disk/by-uuid/${root-partition-uuid}";
    fsType = "btrfs";
    options = [ "subvol=caches/@varcache" ] ++ defaultMountOptions;
    neededForBoot = true;
  };

  fileSystems."/persist/caches/home/diwangs/.cache" = {
    device = "/dev/disk/by-uuid/${root-partition-uuid}";
    fsType = "btrfs";
    options = [ "subvol=caches/@homecache" ] ++ defaultMountOptions;
    neededForBoot = true;
  };

  # Regenerable, so cache rather than state: a restored snapshot could predict
  # boot files no longer on the ESP. If lost, recover before rebooting:
  #   systemctl start systemd-pcrlock-firmware-code \
  #     systemd-pcrlock-secureboot-policy systemd-pcrlock-secureboot-authority
  #   nixos-rebuild boot  # lzbt re-locks stubs/bootloader, then make-policy
  fileSystems."/persist/caches/var/lib/pcrlock.d" = {
    device = "/dev/disk/by-uuid/${root-partition-uuid}";
    fsType = "btrfs";
    options = [ "subvol=caches/@pcrlock" ] ++ defaultMountOptions;
    neededForBoot = true;
  };

  fileSystems."/persist/caches/var/lib/flatpak" = {
    device = "/dev/disk/by-uuid/${root-partition-uuid}";
    fsType = "btrfs";
    options = [ "subvol=caches/@flatpak" ] ++ defaultMountOptions;
    neededForBoot = true;
  };

  # Swap: same size as RAM (64 GiB), disables CoW
  fileSystems."/var/swap" = {
    device = "/dev/disk/by-uuid/${root-partition-uuid}";
    fsType = "btrfs";
    options = [
      "subvol=caches/@swap"
      "nodatacow"
    ]
    ++ defaultMountOptions;
  };

  swapDevices = [
    {
      device = "/var/swap/swapfile";
      size = 64 * 1024; # Accepts MiB
      # NOTE: Gnome system manager uses GB, not GiB
    }
  ];
}
