{ config, lib, pkgs, ... }: {
  # Key management (GNOME)
  # gcr is introduced in 25.11
  services.gnome.gcr-ssh-agent.enable = false;  # For SSH, use gpg-agent
  services.gnome.gnome-keyring.enable = true;   # For non-SSH, use keyring

  # Export SSH_ASKPASS (GNOME sets askPassword to seahorse's helper, but the
  # export defaults to services.xserver.enable, which is off on Wayland-only).
  # Without it, GUI apps (no TTY) can't do FIDO2 PIN entry or touch prompts.
  # enableAskPassword only covers login shells; sessionVariables goes through
  # PAM so it also reaches the systemd user manager (= GNOME-launched apps).
  programs.ssh.enableAskPassword = true;
  # Home Manager exports this for shells, D-Bus activation, and the user
  # manager, but GNOME's desktop launcher inherits its environment from PAM.
  # Give its first VS Code process the PIV agent socket as well.
  environment.sessionVariables.SSH_AUTH_SOCK =
    "/run/user/${toString config.users.users.diwangs.uid}/yubikey-agent/yubikey-agent.sock";
  # environment.sessionVariables.SSH_ASKPASS = config.programs.ssh.askPassword;

  # For Yubikey
  services.pcscd.enable = true;
  services.udev.packages = [ pkgs.yubikey-personalization ];
}