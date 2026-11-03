{
  config,
  lib,
  os-secret,
  ...
}:
{
  home.stateVersion = "25.05";
  home.username = "diwangs";
  home.uid = 1000;

  # User-scoped credential: encrypt with --user --with-key=host+tpm2.
  systemd.user.services.agenix.Service.SetCredentialEncrypted =
    os-secret.systemd-creds.paladin-iii-diwangs.ageIdentity;
  age.identityPaths = lib.mkForce [
    "/run/user/${toString config.home.uid}/credentials/agenix.service/age-identity"
  ];

  # Secrets it can decrypt
  age.secrets."network/ssh-hosts".file = os-secret.network.ssh-hosts;
  age.secrets."token/access-nova.json".file = os-secret.token."access-nova.json";
  age.secrets."token/bedrock".file = os-secret.token.bedrock;

  # SSH config
  programs.ssh = {
    enable = true;
    enableDefaultConfig = false; # Won't be needed in future versions
    includes = [ "/run/user/1000/agenix/network/ssh-hosts" ];
    settings = {
      # Fix bug on VSCode remote SSH
      # https://github.com/microsoft/vscode-remote-release/issues/7814#issuecomment-1905654502
      # NOTE: this seems to be a flaky bug, but fix it anyway
      "*" = {
        ForwardAgent = true;
        IdentityAgent = "/run/user/1000/yubikey-agent/yubikey-agent.sock";
        # Keep idle sessions (e.g. Zed remote) alive through proxies/NAT
        ServerAliveInterval = 60;
        ServerAliveCountMax = 3;
      };
    };
  };
}
