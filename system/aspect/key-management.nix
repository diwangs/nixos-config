{ config, lib, pkgs, ... }: {
  # Key management (GNOME)
  # gcr is introduced in 25.11
  services.gnome.gcr-ssh-agent.enable = false;  # For SSH, use gpg-agent
  services.gnome.gnome-keyring.enable = true;   # For non-SSH, use keyring

  # For Yubikey
  services.pcscd.enable = true;
  services.udev.packages = [ pkgs.yubikey-personalization ];
}