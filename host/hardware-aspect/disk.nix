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
  boot.initrd.availableKernelModules = [
    "dm-integrity"
    "aegis128-aesni"
    "aegis128" # software-backed alg as backup
  ];
  boot.initrd.systemd.tpm2.enable = true;

  # Boot partition: EFI System Partition
  fileSystems."/boot" = {
    device = "/dev/disk/by-uuid/${boot-partition-uuid}";
    fsType = "vfat";
    # Owner-only access: bootctl refuses a world-readable random seed
    options = [ "umask=0077" ];
  };

  # Root partition: tmpfs, so nothing on it survives a reboot. Without size=,
  # the kernel caps it at 50% of RAM. To set a cap, add e.g. "size=2G" to the
  # options below.
  fileSystems."/" = {
    device = "none";
    fsType = "tmpfs";
    options = [
      "defaults"
      "mode=755" # tmpfs defaults to 1777
    ];
  };

  boot.initrd.luks.devices."decrypted_root" = {
    device = "/dev/nvme0n1p2";
    bypassWorkqueues = true;
  };

  # Persistent storage: each subvolume is mounted under /persist in initrd, and
  # impermanence bind-mounts it into place (see host/paladin-iii.nix). The
  # /persist parents live on the tmpfs root, so anything persisted must
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

  # Caches: persistent, non-snapshoted data. Ones that are "regenerable"

  # Mounted directly: the store must exist before any bind mount
  fileSystems."/nix" = {
    device = "/dev/disk/by-uuid/${root-partition-uuid}";
    fsType = "btrfs";
    options = [ "subvol=caches/@nix" ] ++ defaultMountOptions;
  };

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
      # NOTE: GNOME system manager uses GB, not GiB
    }
  ];
}
