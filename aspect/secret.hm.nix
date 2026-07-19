{ config, ... }: {
  age.identityPaths = [
    "${config.home.homeDirectory}/.local/state/nix/secret/.age-identity"
  ];

  # programs.gpg.enable = true;
  # services.gpg-agent = {
  #   enable = true; # GPG only (git commit signing); SSH moved to yubikey-agent below
  #   enableSshSupport = false;
  #   enableScDaemon = false; # Conflicts with pcscd,
  #   pinentry = {
  #     package = pkgs.pinentry-gnome3;
  #   };
  # };
}
