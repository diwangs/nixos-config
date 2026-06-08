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
    settings = {
      "paladin-ii" = {
        HostName = secrets.peripherals.paladin-ii-ssh-hostname;
      };
      "netx11" = {
        HostName = secrets.peripherals.netx11-ssh-hostname;
        ProxyJump = secrets.peripherals.netx11-ssh-proxyjump;
      };
      "nova-diwangs-workspace" = {
        HostName = secrets.peripherals.diwangs-nova-workspace-ssh-hostname;
        User = "admin";
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