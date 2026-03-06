# https://wiki.nixos.org/wiki/Hardware/Framework/Laptop_13
# Additional config that are not covered by nixos-hardware
{ config, lib, pkgs, ... }: {
  # Enable KVM for AMD CPU
	boot.kernelModules = [ "kvm-amd" ];

  # LVFS, instead of MrChromebox script
  services.fwupd.enable = true;

  # Manage battery via tlp exclusively
  # https://github.com/linrunner/TLP/issues/814#issuecomment-3035573617
  # boot.kernelParams = [
	# 	"cros_charge-control.probe_with_fwk_charge_control=1"
	# ];
}