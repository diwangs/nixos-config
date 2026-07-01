# Injects the OFFICIAL Claude Desktop (Anthropic's Debian .deb, repackaged in
# ./package.nix) as `pkgs.claude-desktop`.
#
# Self-contained: the .deb is fetched by the pinned URL+hash in ./package.nix,
# so — unlike ../claude-desktop-bin/base.nix — this overlay needs NO flake
# input. Import it in ../../nixos.nix's `nixpkgs.overlays` INSTEAD OF the
# claude-desktop-bin base + patches (both define `claude-desktop`; the last
# overlay wins, so don't enable both). Not wired in yet — see the plan's
# "Switching over" section.
final: prev: {
  claude-desktop = final.callPackage ./package.nix { };
}
