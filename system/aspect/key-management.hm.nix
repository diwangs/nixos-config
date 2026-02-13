{ config, pkgs, lib, secrets, ... }: {
  # Key management
  programs.gpg.enable = true;
  services.gpg-agent = {
    enable = true;
    enableSshSupport = true;  # This should set SSH_AUTH_SOCK
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
    matchBlocks = {
      "paladin-ii" = {
        hostname = secrets.peripherals.paladin-ii-ssh-hostname;
      };
      "netx11" = {
        hostname = secrets.peripherals.netx11-ssh-hostname;
        proxyJump = secrets.peripherals.netx11-ssh-proxyjump;
      };
      # Fix bug on VSCode remote SSH
      # https://github.com/microsoft/vscode-remote-release/issues/7814#issuecomment-1905654502
      # NOTE: this seems to be a flaky bug, but fix it anyway
      "*" = {
        forwardAgent = true;
        identityAgent = "/run/user/1000/gnupg/S.gpg-agent.ssh";
      };
    };
  };
}