# https://wiki.nixos.org/wiki/Hardware/Framework/Laptop_13
# Additional config that are not covered by nixos-hardware
{ config, lib, pkgs, ... }: {
  # Enable KVM for AMD CPU
	boot.kernelModules = [ "kvm-amd" ];

  # LVFS, instead of MrChromebox script
  services.fwupd.enable = true;
}