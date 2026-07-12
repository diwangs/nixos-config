{ config, pkgs, lib, secrets, ... }: {
  # Key management
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
  # NOTE: holds a persistent PIV transaction — stop the unit before using
  # age-plugin-yubikey/ykman (agenix editing uses the host key instead).
  # This is a less exclusive hold than gpg's scdaemon.
  # NOTE: the 9a key is pin-policy=once, touch=never (fp 3oSftftMh33…).
  services.yubikey-agent.enable = true;
  systemd.user.services.yubikey-agent.Service.Environment =
    # the binary execs plain `pinentry` from PATH (package doesn't wrap it)
    "PATH=${lib.makeBinPath [ pkgs.pinentry-gnome3 ]}:/run/current-system/sw/bin";

  # SSH config
  programs.ssh = {
    enable = true;
    enableDefaultConfig = false;  # Won't be needed in future versions
    includes = [ "/run/agenix/ssh-hosts" ];
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