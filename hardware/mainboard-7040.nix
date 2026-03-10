# https://wiki.nixos.org/wiki/Hardware/Framework/Laptop_13
# Additional config that are not covered by nixos-hardware
{ config, lib, pkgs, ... }: {
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
}