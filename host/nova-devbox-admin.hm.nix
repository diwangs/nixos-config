{ pkgs, os-secret, ... }: {
  home.username = "admin";
  home.homeDirectory = "/home/admin";
  home.stateVersion = "25.05";

  # Non-NixOS Linux hosts need profile/session glue that NixOS
  # normally provides.
  targets.genericLinux.enable = true;
  xdg.enable = true;
  manual.manpages.enable = true;

  # Secrets it can decrypt
  age.secrets."token/bedrock".file = os-secret.token.bedrock;

  # Headless tools that NixOS provides system-wide on the laptop
  home.sessionVariables.EDITOR = "nano"; # laptop: code-wait (system)
  home.sessionPath = [ "$HOME/.local/bin" ];
  home.packages = with pkgs; [
    nano
    ripgrep
    tree
    htop
    wget
    curl
    unzip
    zip
    rsync
  ];
}
