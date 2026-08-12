# Provides `pkgs.chatgpt` from the upstream nixpkgs draft Linux packaging in
# PR #551713 (https://github.com/NixOS/nixpkgs/pull/551713), synced by
# ./pull.sh. It overrides nixpkgs's current Darwin-only package while the PR is
# open.
#
# ./package.nix, ./source.nix, ./launcher.nix, and ./update.sh are vendored
# copies — do not hand-edit them. Re-run ./pull.sh to sync with new PR commits
# (pin tracked in ./.pinned-rev).
final: prev: {
  chatgpt = final.callPackage ./package.nix { };
}
