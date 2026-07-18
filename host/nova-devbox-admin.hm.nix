{ config, lib, pkgs, age-secrets, ... }: {
  home.username = admin;
  home.homeDirectory = "/home/admin";
  home.stateVersion = "25.05";

  # Non-NixOS Linux hosts need profile/session glue that NixOS
  # normally provides.
  targets.genericLinux.enable = true;
  xdg.enable = true;
  manual.manpages.enable = true;

  home.sessionVariables.EDITOR = "nano"; # laptop: code-wait (system)
  home.sessionPath = [ "$HOME/.local/bin" ];

  # Headless tools that NixOS provides system-wide on the laptop
  home.packages = with pkgs; [
    nano
    ripgrep
    tree
    htop
    tmux
    wget
    curl
    unzip
    zip
    rsync
  ];

  age.identityPaths = [ "/nix/secret/nova-devbox.key" ];
	age.secrets."token/bedrock".file = age-secrets.token.bedrock;
}
