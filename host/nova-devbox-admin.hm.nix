{
  config,
  pkgs,
  os-secret,
  ...
}:
{
  home.stateVersion = "25.05";
  home.username = "admin";
  home.homeDirectory = "/home/admin";

  # Non-NixOS Linux hosts need profile/session glue that NixOS
  # normally provides.
  targets.genericLinux.enable = true;
  xdg.enable = true;
  manual.manpages.enable = true;

  /*
    Plaintext identity: only the devbox still uses this. NixOS hosts use a
    systemd-creds identity at
    /run/user/<uid>/credentials/agenix.service/age-identity instead (see
    host/*-diwangs.hm.nix).

    To move the devbox to systemd-creds too, it needs systemd >= 256 (user
    credentials) and an enabled systemd-creds.socket, since a rootless user
    can't create /var/lib/systemd/credential.secret. Enroll locally, like oo7
    in aspect/secret.nix, so the blob never lands in os-secret:
      systemd-creds encrypt --user --with-key=host+tpm2 --name=age-identity \
        ~/.age-identity-pq ~/.config/credstore.encrypted/age-identity
    then `LoadCredentialEncrypted = "age-identity"` on agenix.service (no path
    searches the user credstore) and point this at the path above.
  */
  age.identityPaths = [
    "${config.home.homeDirectory}/.age-identity-pq"
  ];

  # Secrets it can decrypt
  age.secrets."token/bedrock".file = os-secret.token.bedrock;

  # No Secret Service on this rootless host; keyring elsewhere (oo7)
  programs.codex.settings.cli_auth_credentials_store = "file";

  # Headless tools that NixOS provides system-wide on the laptop
  home.sessionPath = [ "$HOME/.local/bin" ];
  home.packages = with pkgs; [
    nano
    ripgrep
    tree
    htop
    wget
    curl
    unzip
    zip
    rsync
  ];
}
