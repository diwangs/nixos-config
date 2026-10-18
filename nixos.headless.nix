# Portable system profile for headless NixOS guests. It is a strict subset of
# the laptop: nixos.nix imports this file and adds the desktop on top.
# Requires the home-manager NixOS module, loaded per host in flake.nix.
{
  lib,
  pkgs,
  agenix,
  allowedUnfree,
  ...
}:
{
  imports = [
    agenix.nixosModules.default

    ./aspect/locale.nix
    ./aspect/user.nix
    ./aspect/secret.nix
    ./aspect/shell.nix
  ];

  # Shell + headless packages/agents; the laptop's home-manager.nix extends it
  home-manager.users.diwangs.imports = [ ./home-manager.headless.nix ];

  nix.settings.experimental-features = [
    "nix-command"
    "flakes"
  ];
  nixpkgs.overlays = [
    (import ./package/overlay/landstrip/overlay.nix)
    # oo7 → git main (aws-vault content type + portal token fixes). See
    # package/overlay/oo7.nix.
    (import ./package/overlay/oo7.nix)
    # (import ./package/overlay/codex/overlay.nix)
    # (import ./package/overlay/codex-acp/overlay.nix)
  ];
  nixpkgs.config.allowUnfreePredicate =
    pkg: builtins.elem (lib.getName pkg) allowedUnfree;

  security.apparmor.enable = true;
  programs.nix-ld.enable = true;
  environment.systemPackages = with pkgs; [
    cloud-utils
    cryptsetup
    git
    jq
    nano
    rsync
  ];
}
