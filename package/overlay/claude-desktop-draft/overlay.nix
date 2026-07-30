# Provides `pkgs.claude-desktop` from the UPSTREAM nixpkgs draft packaging —
# pulled verbatim from PR #537215 (https://github.com/NixOS/nixpkgs/pull/537215)
# by ./pull.sh. This is now the dogfooded `claude-desktop`: it REPLACES the
# local ../claude-desktop/overlay.nix base (kept on disk but disabled in
# ../../../nixos.nix). The sibling app.asar patch overlays
# (../claude-desktop/patch/*) still layer on top of it — they override whatever
# `prev.claude-desktop` is, so import them AFTER this one.
#
# The directory keeps the `-draft` name because it tracks the still-open PR; the
# produced attribute is plain `claude-desktop`.
#
# ./package.nix and ./update.sh are VENDORED copies — do not hand-edit them.
# Re-run ./pull.sh to sync with new PR commits (pin tracked in ./.pinned-rev).
final: prev: {
  claude-desktop = final.callPackage ./package.nix { };
}
