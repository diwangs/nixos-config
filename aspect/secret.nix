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

  # TODO: this is user secrets, move to HM
  # Drop-in to oo7-daemon to enable auto-unlock via agenix at login
  systemd.user.services.oo7-daemon = {
    after = [ "agenix.service" ];
    wants = [ "agenix.service" ];
    serviceConfig.ImportCredential = ""; # Don't use systemd-creds yet
    # Make sure there's a file called `oo7.keyring-encryption-password` here
    environment.CREDENTIALS_DIRECTORY = "/run/user/1000/agenix/paladin-iii";
  };
}
