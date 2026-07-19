{ age-secrets, ... }: {
  home.username = "diwangs";
  home.stateVersion = "25.05";

  age.identityPaths = [
    "/home/diwangs/.local/state/nix/secret/.age-identity"
  ];

  # Decrypt files to `/run/user/$UID/agenix/`
  age.secrets."network/ssh-hosts".file = age-secrets.network.ssh-hosts;
  age.secrets."token/bedrock".file = age-secrets.token.bedrock;

  programs.ssh.includes = [ "/run/user/1000/agenix/network/ssh-hosts" ];
}
