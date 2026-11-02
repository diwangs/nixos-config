# System packages shared between the laptop and headless NixOS guests,
# imported by nixos.headless.nix (which nixos.nix layers package/nixos.nix on
# top of). Keep this list headless: no desktop, firmware, or
# hardware-specific assumptions.
{ pkgs, ... }:
{
  # nix-ld: for packages that hasn't been nixified e.g., `uv`-managed Python,
  # `fnm`-managed Node
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
