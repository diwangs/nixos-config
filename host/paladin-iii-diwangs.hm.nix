{ age-secrets, ... }: {
  home.username = "diwangs";
  home.stateVersion = "25.05";

  # Secrets it can decrypt
  age.secrets."paladin-iii/oo7.keyring-encryption-password".file =
    age-secrets.paladin-iii."oo7.keyring-encryption-password";
  age.secrets."network/ssh-hosts".file = age-secrets.network.ssh-hosts;
  age.secrets."token/bedrock".file = age-secrets.token.bedrock;

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
      };
    };
  };
}
