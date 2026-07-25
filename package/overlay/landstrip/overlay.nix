# Injects landstrip (the OS-level sandbox runner repackaged in ./package.nix) as
# `pkgs.landstrip`. Import it in ../../../nixos.nix and ../../../flake.nix's
# `nixpkgs.overlays`. See ./package.nix for what consumes it.
final: prev: {
  landstrip = final.callPackage ./package.nix { };
}
