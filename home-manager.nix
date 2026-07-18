# home-manager configuration for diwangs
{ ... }: {
  imports = [
    # Shared with rootless devboxes (shell + headless packages/agents)
    ./home-manager.devbox.nix

    ./aspect/desktop.hm.nix
    ./aspect/yubikey.hm.nix

    ./package/home-manager.nix
  ];
}
