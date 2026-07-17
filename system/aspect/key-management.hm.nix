{ config, pkgs, lib, secrets, ... }: {
  # TODO: disable GPG entirely
  programs.gpg.enable = true;
  services.gpg-agent = {
    enable = true;            # GPG only (git commit signing); SSH moved to yubikey-agent below
    enableSshSupport = false;
    enableScDaemon = false;   # Conflicts with pcscd, 
    pinentry = {
      package = pkgs.pinentry-gnome3;
    };
  };

  # SSH: uses YubiKey to store the secret key. We use PIV-based for balance
  # of app compatibility (i.e., pinentry-support, card-agent exclusivity):
  # - FIDO2 is buggy in some GUI frontend (e.g., Claude Desktop interprets
  #   waiting for touch as error, and no-touch is even more buggy)
  # - OpenPGP scdaemon conflicts with pcscd, making YubiKey Manager GUI stuck
  # NOTE: holds a persistent PIV transaction - stop the unit before using
  # age-plugin-yubikey/ykman (agenix editing uses the host key instead).
  # This is a less exclusive hold than gpg's scdaemon.
  # NOTE: the 9a key is pin-policy=once, touch=never.
  services.yubikey-agent.enable = true;
  # yubikey-agent 0.1.6 does not consume systemd-activated sockets: it always
  # opens the path passed to `-l`. Home Manager's socket unit therefore strands
  # the connection that triggered activation, while later connections reach the
  # agent's replacement listener. Run the listener eagerly, as upstream's unit
  # does; the YubiKey itself is still opened lazily on the first agent request.
  sshAuthSock.systemd.socketProviderUnit = lib.mkForce "yubikey-agent.service";
  systemd.user.sockets.yubikey-agent = lib.mkForce { };
  home.activation.stopBrokenYubikeySocket =
    lib.hm.dag.entryBetween [ "reloadSystemd" ] [ "linkGeneration" ] ''
      run ${pkgs.systemd}/bin/systemctl --user stop yubikey-agent.socket || true
      socketLink="$HOME/.config/systemd/user/sockets.target.wants/yubikey-agent.socket"
      if [ -L "$socketLink" ]; then
        run rm -f "$socketLink"
      fi
    '';
  systemd.user.services.yubikey-agent = {
    Unit = {
      Requires = lib.mkForce [ ];
      After = lib.mkForce [ ];
      RefuseManualStart = lib.mkForce false;
    };
    Service = {
      # The binary execs plain `pinentry` from PATH (package isn't wrapped).
      Environment =
        "PATH=${lib.makeBinPath [ pkgs.pinentry-gnome3 ]}:/run/current-system/sw/bin";
      RuntimeDirectory = "yubikey-agent";
    };
    Install.WantedBy = [ "default.target" ];
  };

  # SSH config
  programs.ssh = {
    enable = true;
    enableDefaultConfig = false;  # Won't be needed in future versions
    includes = [ "/run/agenix/network/ssh-hosts" ];
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
