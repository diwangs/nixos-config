{ pkgs, agenix, age-secrets, ... }: {
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

  # Secret management (agenix)
  # Runtime-only: secrets decrypt at activation into /run/agenix/*. Eval-time
  # values (partition UUIDs, hostnames, keygrips, ...) stay in secret.toml.
  #
  # Every .age file is encrypted to both identities (secrets/secret.nix):
  # - Machine (unattended decrypt at boot): dedicated host key, configured in
  #   flake.nix, NOT in git, no sshd involved. Back it up offline.
  # - Human (agenix -e): YubiKey PIV P-256 via age-plugin-yubikey.
  # systemd.tmpfiles.rules = [ "d /nix/secret 0700 root root -" ];

  # Use rage (Rust) instead of Go age, for both boot-time decryption and the
  # editing CLI. Same format + plugin protocol, so .age files are unaffected.
  age.ageBin = "${pkgs.rage}/bin/rage";

  # agenix CLI + YubiKey plugin for editing/encrypting secrets on this host
  environment.systemPackages = [
    (agenix.packages.${pkgs.stdenv.hostPlatform.system}.default.override {
      ageBin = "${pkgs.rage}/bin/rage";
    })
    pkgs.rage # for manual decrypt/inspect (matches what boot activation runs)
    pkgs.age-plugin-yubikey
  ];

  # Unlike HM, this doesn't depend on UID
  age.identityPaths = [ "/etc/nixos/.age-identity" ];
}
