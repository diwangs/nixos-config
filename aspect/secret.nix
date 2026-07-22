{ pkgs, agenix, ... }: {
  # oo7: Secret Portal and Secret Service
  services.oo7.enable = true;
  services.gnome.gnome-keyring.enable = false;

  # Drop-in to oo7-daemon to enable auto-unlock via agenix at login
  systemd.user.services.oo7-daemon = {
    after = [ "agenix.service" ];
    wants = [ "agenix.service" ];
    serviceConfig.ImportCredential = ""; # reset the systemd-creds credstore import
    environment.CREDENTIALS_DIRECTORY = "/run/user/1000/agenix/paladin-iii";
  };

  # SSH: we use yubikey-agent
  programs.ssh.enableAskPassword = true; # export SSH_ASKPASS
  services.gnome.gcr-ssh-agent.enable = false; # disable GCR SSH agent (25.11)

  # agenix: general secret management

  # Unlike HM, this doesn't depend on UID
  # Make sure it resides in a mountpoint that is `neededForBoot`
  # If it is ever changed, be sure to switch twice for measured boot
  age.identityPaths = [ "/nix/secret/.age-identity" ];

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
}
