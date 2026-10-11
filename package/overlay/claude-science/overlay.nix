# Injects Claude Science (Anthropic's research workbench, the prebuilt Linux
# binary repackaged in ./package.nix) as `pkgs.claude-science`.
#
# Self-contained: the binary is fetched by the pinned URL+hash in ./package.nix
# (maintained by ./update.sh), so this overlay needs no flake input. Import it
# in ../../../nixos.nix's `nixpkgs.overlays`.
final: prev: {
  claude-science = final.callPackage ./package.nix { };
}
