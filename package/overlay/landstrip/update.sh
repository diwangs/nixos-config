#!/usr/bin/env bash
# Update the landstrip pin in package.nix to the latest release from
# landstrip/landstrip. Rewrites `version`, the fetchFromGitHub `hash`, and the
# `cargoHash` in place.
#
# Usage:
#   ./update.sh              # pin to the latest GitHub release
#   ./update.sh 0.18.0       # pin to a specific version/tag
#
# The source hash is resolved with `nix flake prefetch` (the sandbox denies the
# O_PATH that `nix-prefetch-url --unpack` needs). The cargoHash cannot be
# fetched — it is derived from the vendored crate set — so we obtain it the
# standard way: pin a fake hash, build, and read the "got:" hash back out of the
# mismatch error.
#
# Requires: curl, jq, nix (flakes enabled), sed (GNU).

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LANDSTRIP_NIX="$SCRIPT_DIR/package.nix"
FLAKE_DIR="$SCRIPT_DIR/../../.."

# lib.fakeHash — a syntactically valid SRI hash that no real output matches, so
# the build fails fast with the true hash in its error.
FAKE_HASH="sha256-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA="

err()  { printf 'error: %s\n' "$*" >&2; exit 1; }
info() { printf '==> %s\n' "$*"; }

for cmd in curl jq nix sed; do
  command -v "$cmd" >/dev/null || err "missing required command: $cmd"
done
[[ -f "$LANDSTRIP_NIX" ]] || err "package.nix not found at $LANDSTRIP_NIX"

if [[ $# -ge 1 ]]; then
  tag="$1"
else
  info "Resolving latest release from landstrip/landstrip..."
  tag=$(curl -fsSL "https://api.github.com/repos/landstrip/landstrip/releases/latest" \
        | jq -r '.tag_name')
  [[ -n "$tag" && "$tag" != "null" ]] || err "could not resolve latest release tag"
fi
info "Target tag: $tag"

cur_version=$(grep -oE 'version *= *"[^"]+"' "$LANDSTRIP_NIX" | head -n1 \
              | grep -oE '"[^"]+"' | tr -d '"')
[[ -n "$cur_version" ]] || err "could not parse current version from package.nix"

# Build the unpatched package through the flake's own nixpkgs input, so the
# cargoHash matches what the system build will vendor. Keep this separate from
# the overlay build: an outdated downstream patch can fail before Nix reports
# the expected fake-hash mismatch.
build_upstream_landstrip() {
  nix build --no-link --impure --expr "
    let
      flake = builtins.getFlake \"$(cd "$FLAKE_DIR" && pwd)\";
      pkgs = import flake.inputs.nixpkgs { system = builtins.currentSystem; };
    in pkgs.callPackage $LANDSTRIP_NIX { }
  " 2>&1
}

# Verify the package exactly as the system consumes it, including the local
# policy-extension patch from overlay.nix.
build_landstrip() {
  nix build --no-link --impure --expr "
    let
      flake = builtins.getFlake \"$(cd "$FLAKE_DIR" && pwd)\";
      pkgs = import flake.inputs.nixpkgs {
        system = builtins.currentSystem;
        overlays = [ (import $SCRIPT_DIR/overlay.nix) ];
      };
    in pkgs.landstrip
  " 2>&1
}

# Grab the real "got:" SRI hash out of a fixed-output hash-mismatch error.
extract_got_hash() {
  grep -oE 'got: *sha256-[A-Za-z0-9+/=]+' | head -n1 | grep -oE 'sha256-[A-Za-z0-9+/=]+'
}

info "Fetching source hash for $tag..."
src_hash=$(nix flake prefetch "github:landstrip/landstrip/${tag}" --json 2>/dev/null \
           | jq -r '.hash')
[[ -n "$src_hash" && "$src_hash" != "null" ]] || err "failed to prefetch source for $tag"
info "source hash: $src_hash"

# Set version, source hash, and a fake cargoHash. The source hash must be
# correct first — otherwise the build fails fetching the source, before it ever
# reaches (and reports) the cargo vendor hash.
version="${tag#v}"
sed -i -E \
  -e "s|(version *= *)\"[^\"]+\"|\\1\"${version}\"|" \
  -e "s|(tag *= *)version;|\\1version;|" \
  "$LANDSTRIP_NIX"
sed -i -E "0,/hash *= *\"[^\"]+\";/ s||hash = \"${src_hash}\";|" "$LANDSTRIP_NIX"
sed -i -E "s|cargoHash *= *\"[^\"]+\"|cargoHash = \"${FAKE_HASH}\"|" "$LANDSTRIP_NIX"

info "Computing cargoHash (a hash-mismatch build failure is expected)..."
build_out=$(build_upstream_landstrip || true)
cargo_hash=$(echo "$build_out" | extract_got_hash || true)
if [[ -z "$cargo_hash" ]]; then
  echo "$build_out" >&2
  err "could not extract cargoHash from build output"
fi
info "cargoHash: $cargo_hash"
sed -i -E "s|cargoHash *= *\"[^\"]+\"|cargoHash = \"${cargo_hash}\"|" "$LANDSTRIP_NIX"

info "Verifying the final pin builds..."
if ! build_landstrip >/dev/null 2>&1; then
  err "landstrip failed to build with the new pin; inspect package.nix"
fi

info "Updated landstrip: $cur_version -> $version. Review the diff before committing."
