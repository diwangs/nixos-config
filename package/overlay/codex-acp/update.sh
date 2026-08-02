#!/usr/bin/env bash
# Update the codex-acp pin in package.nix to the latest release from
# agentclientprotocol/codex-acp. Rewrites `version`, the fetchFromGitHub
# `hash`, and `npmDepsHash` in place.
#
# Usage:
#   ./update.sh              # pin to the latest GitHub release
#   ./update.sh 1.1.9        # pin to a specific version (without the v prefix)
#
# The source hash is resolved with `nix flake prefetch` (the sandbox denies the
# O_PATH that `nix-prefetch-url --unpack` needs). Unlike a Cargo vendor hash,
# npmDepsHash can be computed directly from the fetched package-lock.json with
# nixpkgs' own `prefetch-npm-deps`, no fake-hash build round-trip needed.
#
# Requires: curl, jq, nix (flakes enabled), sed (GNU).

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CODEX_ACP_NIX="$SCRIPT_DIR/package.nix"
FLAKE_DIR="$SCRIPT_DIR/../../.."

err()  { printf 'error: %s\n' "$*" >&2; exit 1; }
info() { printf '==> %s\n' "$*"; }

for cmd in curl jq nix sed; do
  command -v "$cmd" >/dev/null || err "missing required command: $cmd"
done
[[ -f "$CODEX_ACP_NIX" ]] || err "package.nix not found at $CODEX_ACP_NIX"

if [[ $# -ge 1 ]]; then
  tag="v$1"
else
  info "Resolving latest release from agentclientprotocol/codex-acp..."
  tag=$(curl -fsSL "https://api.github.com/repos/agentclientprotocol/codex-acp/releases/latest" \
        | jq -r '.tag_name')
  [[ -n "$tag" && "$tag" != "null" ]] || err "could not resolve latest release tag"
fi
info "Target tag: $tag"

cur_version=$(grep -oE 'version *= *"[^"]+"' "$CODEX_ACP_NIX" | head -n1 \
              | grep -oE '"[^"]+"' | tr -d '"')
[[ -n "$cur_version" ]] || err "could not parse current version from package.nix"

# callPackage the package through the flake's own nixpkgs input, so
# npmDepsHash matches what the system build will vendor.
build_codex_acp() {
  nix build --no-link --impure --expr "
    let
      flake = builtins.getFlake \"$(cd "$FLAKE_DIR" && pwd)\";
      pkgs = import flake.inputs.nixpkgs { system = builtins.currentSystem; };
    in pkgs.callPackage $CODEX_ACP_NIX { }
  " 2>&1
}

prefetch_npm_deps_bin() {
  nix build --no-link --print-out-paths --impure --expr "
    let
      flake = builtins.getFlake \"$(cd "$FLAKE_DIR" && pwd)\";
      pkgs = import flake.inputs.nixpkgs { system = builtins.currentSystem; };
    in pkgs.prefetch-npm-deps
  "
}

info "Fetching source for $tag..."
prefetch_json=$(nix flake prefetch "github:agentclientprotocol/codex-acp/${tag}" --json 2>/dev/null)
src_hash=$(echo "$prefetch_json" | jq -r '.hash')
src_path=$(echo "$prefetch_json" | jq -r '.storePath')
[[ -n "$src_hash" && "$src_hash" != "null" ]] || err "failed to prefetch source for $tag"
[[ -n "$src_path" && -f "$src_path/package-lock.json" ]] || err "prefetched source has no package-lock.json"
info "source hash: $src_hash"

info "Computing npmDepsHash..."
npm_deps_bin=$(prefetch_npm_deps_bin)
npm_deps_hash=$("$npm_deps_bin/bin/prefetch-npm-deps" "$src_path/package-lock.json")
[[ -n "$npm_deps_hash" ]] || err "could not compute npmDepsHash"
info "npmDepsHash: $npm_deps_hash"

version="${tag#v}"
sed -i -E \
  -e "s|(version *= *)\"[^\"]+\"|\\1\"${version}\"|" \
  "$CODEX_ACP_NIX"
sed -i -E "0,/hash *= *\"[^\"]+\";/ s||hash = \"${src_hash}\";|" "$CODEX_ACP_NIX"
sed -i -E "s|npmDepsHash *= *\"[^\"]+\"|npmDepsHash = \"${npm_deps_hash}\"|" "$CODEX_ACP_NIX"

info "Verifying the final pin builds..."
if ! build_codex_acp >/dev/null 2>&1; then
  err "codex-acp failed to build with the new pin; inspect package.nix"
fi

info "Updated codex-acp: $cur_version -> $version. Review the diff before committing."
