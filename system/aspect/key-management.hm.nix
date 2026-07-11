{ config, pkgs, lib, secrets, ... }: {
  # Key management
  programs.gpg.enable = true;
  services.gpg-agent = {
    enable = true;
    enableSshSupport = true;  # This should set SSH_AUTH_SOCK
    enableScDaemon = false;   # Conflicts with Yubikey
    sshKeys = [ 
      secrets.diwangs.gpg-agent-ssh-keygrip # Auth subkey keygrip
    ]; 
    pinentry = {
      # TODO: instead of using pinentry, use YubiKey
      package = pkgs.pinentry-gnome3;
    };
  };
  
  # SSH config
  programs.ssh = {
    enable = true;
    enableDefaultConfig = false;  # Won't be needed in future versions
    includes = [ "/run/agenix/ssh-hosts" ];
    settings = {
      "nova-devbox" = {
        IdentityFile = "~/diwangs-nova.pem";
      };
      # Fix bug on VSCode remote SSH
      # https://github.com/microsoft/vscode-remote-release/issues/7814#issuecomment-1905654502
      # NOTE: this seems to be a flaky bug, but fix it anyway
      "*" = {
        ForwardAgent = true;
        IdentityAgent = "/run/user/1000/gnupg/S.gpg-agent.ssh";
      };
    };
  };
}