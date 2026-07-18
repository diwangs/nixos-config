{ pkgs, ... }: {
  # TODO: disable GPG entirely
  programs.gpg.enable = true;
  services.gpg-agent = {
    enable = true; # GPG only (git commit signing); SSH moved to yubikey-agent below
    enableSshSupport = false;
    enableScDaemon = false; # Conflicts with pcscd,
    pinentry = {
      package = pkgs.pinentry-gnome3;
    };
  };

  # SSH config (user-specific includes depend separately)
  programs.ssh = {
    enable = true;
    enableDefaultConfig = false; # Won't be needed in future versions
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
