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

  # Fix systemd ordering cycle that prevents gpg-agent-ssh.socket from starting
  # at login. Home Manager's `enableSshSupport` emits `set-SSH_AUTH_SOCK.service`
  # with `Before=gpg-agent-ssh.socket`; as an ordinary service it also gets an
  # implicit `After=basic.target`, and `basic.target` is ordered after
  # `sockets.target` (which contains gpg-agent-ssh.socket) -> ordering cycle.
  # systemd breaks the cycle by dropping the socket's start job, so the SSH
  # socket (S.gpg-agent.ssh) is never created and SSH auth via gpg-agent fails.
  # Disabling default dependencies removes the implicit `After=basic.target`,
  # breaking the cycle while keeping the explicit `Before=gpg-agent-ssh.socket`.

  # BUG: Sometimes `S.gpg-agent.ssh` is not created due to systemd breaking a
  # cyclic dependencies. 
  # ... or, just restart the systemd services.
  # systemd.user.services."set-SSH_AUTH_SOCK".Unit.DefaultDependencies = false;
  
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
      "nova-devbox" = {
        HostName = secrets.peripherals.nova-devbox-ssh-hostname;
        User = "admin";
        IdentityFile = "~/diwangs-nova.pem";
      };
      "dsai-arch-devbox" = {
        HostName = secrets.peripherals.dsai-arch-devbox-ssh-hostname;
        User = "ssangdi1";
        ProxyJump = secrets.peripherals.netx11-ssh-proxyjump;
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