{ pkgs, agenix, ... }: {
  # SSH: we use yubikey-agent
  programs.ssh.enableAskPassword = true; # export SSH_ASKPASS
  services.gnome.gcr-ssh-agent.enable = false; # disable GCR SSH agent (25.11)

  # agenix CLI + YubiKey plugin for editing/encrypting secrets on this host
  age.identityPaths = [
    "/run/credentials/agenix-install-secrets.service/age-identity"
  ];
  environment.systemPackages = [
    agenix.packages.${pkgs.stdenv.hostPlatform.system}.default
    pkgs.age # NOTE: don't use `rage` since it hasn't supported pq keys yet
    pkgs.age-plugin-yubikey
  ];

  # oo7: Secret Portal and Secret Service for session secrets
  services.oo7.enable = true;
  services.gnome.gnome-keyring.enable = false;

  # oo7 imports oo7.keyring-encryption-password from the user credstore
  # (upstream ImportCredential=); the encrypted blob is local, not in Nix.
  # Enroll: systemd-ask-password -n | systemd-creds encrypt --user \
  #   --with-key=host+tpm2 --name=oo7.keyring-encryption-password - \
  #   ~/.config/credstore.encrypted/oo7.keyring-encryption-password
  systemd.user.tmpfiles.rules = [
    "d %h/.config/credstore.encrypted 0700 - - -"
  ];
}
