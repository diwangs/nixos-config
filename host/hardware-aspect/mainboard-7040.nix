# https://wiki.nixos.org/wiki/Hardware/Framework/Laptop_13
# Additional config that are not covered by nixos-hardware
{ ... }:
{
  # fwupd: force AMD Platform Secure Boot to "Enabled" in HSI. LOCAL OVERRIDE,
  # NOT A FIX: this board ships with PSB unfused (the PSP's ccp sysfs
  # `boot_integrity` reads 0), it's just nice to have the only blocker to
  # HSI 1+ be removed :)
  nixpkgs.overlays = [
    (final: prev: {
      fwupd = prev.fwupd.overrideAttrs (old: {
        patches = (old.patches or [ ]) ++ [
          ../../package/overlay/fwupd/7040-force-platform-secure-boot.patch
        ];
      });
    })
  ];

  # Enable KVM for AMD CPU
  boot.kernelModules = [ "kvm-amd" ];

  # LVFS, instead of MrChromebox script
  services.fwupd.enable = true;

  # Manage battery via tlp exclusively
  # 260310 NOTE: as of BIOS 3.18 and kernel 6.18, this is broken
  # https://github.com/linrunner/TLP/issues/814#issuecomment-3035573617
  # https://github.com/FrameworkComputer/SoftwareFirmwareIssueTracker/issues/85
  # The alternative is to run `sudo framework_tool --charge-limit 55`
  # boot.kernelParams = [
  # 	"cros_charge-control.probe_with_fwk_charge_control=1"
  # ];

  # Disable since out-of-tree module marks the kernel tainted. This disables
  # custom battery control too. Just control it from the firmware.
  hardware.framework.enableKmod = false;
}
