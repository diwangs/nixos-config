# Portable system profile for headless NixOS guests. The laptop keeps its
# desktop-oriented nixos.nix; shared aspects are imported directly here.
{
  lib,
  pkgs,
  allowedUnfree,
  ...
}:
{
  imports = [
    ./aspect/locale.nix
    ./aspect/user.nix
    ./aspect/shell.nix
  ];

  nix.settings.experimental-features = [
    "nix-command"
    "flakes"
  ];
  nixpkgs.overlays = [
    (import ./package/overlay/landstrip/overlay.nix)
    (import ./package/overlay/codex/overlay.nix)
    (import ./package/overlay/codex-acp/overlay.nix)
  ];
  nixpkgs.config.allowUnfreePredicate =
    pkg: builtins.elem (lib.getName pkg) allowedUnfree;

  security.apparmor.enable = true;
  programs.nix-ld.enable = true;
  environment.systemPackages = with pkgs; [
    age
    cloud-utils
    cryptsetup
    git
    jq
    nano
    rsync
  ];
}
