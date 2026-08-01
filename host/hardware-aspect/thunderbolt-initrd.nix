/*
  Authorize known Thunderbolt docks in stage 1, so that peripherals behind them
  (notably an external keyboard) are usable at the LUKS passphrase prompt.

  The 7040's AMD USB4 host runs the *software* connection manager: the domains
  expose no `boot_acl`, and `<device>/boot` reads 0, so the firmware never
  establishes the tunnel on our behalf. `boltd` only starts after switch-root,
  so without this the dock sits at `authorized=0` for the whole of initrd —
  no PCIe tunnel, no tunneled xHCI, no keyboard.

  The domains are at security level `user` (SL1), where authorization is a bare
  `1` write with no key exchange. A UUID is therefore not a secret and can be
  presented by a hostile device; what confines it is `iommu_dma_protection=1` on
  both domains. That is the same trade-off as the `iommu` policy already stored
  in boltd for these two docks, extended to pre-boot.

  Tunnel setup, xHCI probe and USB enumeration take a few seconds, while the
  passphrase prompt appears almost immediately. The prompt stays open, so
  keystrokes land once the keyboard shows up — there is just a short wait.

  The enrolled device records are copied from `/var/lib/boltd/devices` when the
  bootloader installs the initrd. Only devices whose stored policy is `iommu`
  are authorized, keeping boltd as the source of truth.
*/

{ pkgs, ... }:
let
  authorizeThunderbolt = pkgs.writeTextFile {
    name = "authorize-thunderbolt";
    destination = "/bin/authorize-thunderbolt";
    executable = true;
    text = ''
      #!/bin/sh

      device="$1"
      IFS= read -r uuid < "$device/unique_id" || exit 0
      record="/.initrd-secrets/var/lib/boltd/devices/$uuid"
      [ -f "$record" ] || exit 0

      while IFS= read -r line; do
        if [ "$line" = "policy=iommu" ]; then
          printf 1 > "$device/authorized"
          exit 0
        fi
      done < "$record"
    '';
  };
in
{
  boot.initrd = {
    availableKernelModules = [ "thunderbolt" ];
    secrets."/var/lib/boltd/devices" = null; # Implicitly copied from the host
    services.udev = {
      binPackages = [ authorizeThunderbolt ];
      rules = ''
        ACTION=="add", SUBSYSTEM=="thunderbolt", ATTR{authorized}=="0", RUN+="${authorizeThunderbolt}/bin/authorize-thunderbolt %S%p"
      '';
    };
  };
}
