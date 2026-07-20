# home-manager configuration for diwangs
{ nix-zed-extensions, ... }: {
  imports = [
    # Shared with rootless devboxes (shell + headless packages/agents)
    ./home-manager.devbox.nix

    ./aspect/desktop.hm.nix
    ./aspect/yubikey.hm.nix

    nix-zed-extensions.homeManagerModules.default

    ./package/home-manager.nix
  ];
}
