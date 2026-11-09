# =====================
# fwupd: detect encrypted swapfile on btrfs-on-LUKS (HSI Kernel.Swap)
# =====================
#
# fwupd's linux-swap plugin maps a swapfile's st_dev to a block device to
# check for encryption (udisks, then a sysfs device-mapper walk for CRYPT-).
# A swapfile on a btrfs subvolume (here /var/swap, subvol caches/@swap on
# /dev/mapper/decrypted_root, see host/hardware-aspect/disk.nix) has an
# anonymous st_dev (major 0) with no /sys/dev/block entry, so both lookups fail
# and `fwupdmgr security` reports "Linux swap: Unencrypted".
#
# linux-swap-mountinfo-fallback.patch: when st_dev can't be resolved, take the
# most specific mount containing the swapfile from /proc/self/mountinfo, map
# its source (incl. /dev/mapper/<name> via sysfs dm/name) to a kernel block
# name, and reuse the existing dm walk. Includes self-tests. Approach proposed
# in https://github.com/fwupd/fwupd/issues/5123 (closed, help wanted).
#
# Written against fwupd 2.1.9. Drop once an equivalent fix lands upstream and
# reaches nixpkgs.
final: prev: {
  fwupd = prev.fwupd.overrideAttrs (old: {
    patches = (old.patches or [ ]) ++ [ ./linux-swap-mountinfo-fallback.patch ];
  });
}
