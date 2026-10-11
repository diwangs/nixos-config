#!/usr/bin/env bash
# Update the pinned Claude Science binary (version + sha8 + hash) in
# package.nix to the latest release in Anthropic's public release bucket (the
# one https://claude.ai/install-claude-science.sh reads).
#
# <base>/latest holds the bare sha8 of the newest release; its manifest.json
# carries the display version and the hex sha256 of each platform binary. We
# take the hash straight from the manifest (the same integrity root upstream's
# installer trusts), so the ~140 MB binary isn't downloaded just to hash it.
# (Set VERIFY_DOWNLOAD=1 to also fetch it and confirm the hash end-to-end.)
#
# Usage:
#   ./update.sh             # pick the latest release
#   ./update.sh 8db2454a    # pin an explicit release sha8 (testing / rollback)
#
# Requires: curl, jq, nix (nix hash convert), sed (GNU), grep.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PACKAGE_NIX="$SCRIPT_DIR/package.nix"

BASE="https://storage.googleapis.com/operon-dist-cf94a20e-f71c-413c-bd00-9e12b1fedf59/operon-releases"
PLATFORM="linux-x64"

err()  { printf 'error: %s\n' "$*" >&2; exit 1; }
info() { printf '==> %s\n' "$*"; }

for cmd in curl jq nix sed grep; do
  command -v "$cmd" >/dev/null || err "missing required command: $cmd"
done
[[ -f "$PACKAGE_NIX" ]] || err "package.nix not found at $PACKAGE_NIX"

if [[ $# -ge 1 ]]; then
  new_sha8="$1"
else
  info "Fetching latest release pointer..."
  new_sha8="$(curl -fsSL "$BASE/latest")" || err "could not fetch $BASE/latest"
fi
[[ "$new_sha8" =~ ^[0-9a-f]{8}$ ]] || err "not a release sha8: $new_sha8"

info "Fetching manifest for $new_sha8..."
manifest="$(curl -fsSL "$BASE/$new_sha8/manifest.json")" \
  || err "release $new_sha8 not found"

new_version="$(jq -r '.version // empty' <<<"$manifest")"
hex_sha="$(jq -r --arg p "$PLATFORM" '.sha256[$p] // empty' <<<"$manifest")"
[[ "$new_version" =~ ^[A-Za-z0-9._+-]+$ ]] || err "unexpected manifest version: $new_version"
[[ "$hex_sha" =~ ^[0-9a-f]{64}$ ]] || err "manifest has no $PLATFORM sha256"

info "Release: $new_version ($new_sha8)"

# hex sha256 (as the manifest records it) -> SRI (as fetchurl wants).
new_sri="$(nix hash convert --hash-algo sha256 --to sri "$hex_sha" 2>/dev/null \
  || nix hash to-sri --type sha256 "$hex_sha" 2>/dev/null)" \
  || err "nix hash convert failed"
[[ "$new_sri" == sha256-* ]] || err "unexpected SRI form: $new_sri"

# Optional end-to-end check: download the binary and confirm it matches.
if [[ "${VERIFY_DOWNLOAD:-0}" == "1" ]]; then
  info "VERIFY_DOWNLOAD=1: prefetching binary to confirm hash..."
  got="$(nix-prefetch-url --type sha256 "$BASE/$new_sha8/operon-$PLATFORM")" \
    || err "prefetch failed"
  got_sri="$(nix hash convert --hash-algo sha256 --to sri "$got" 2>/dev/null \
    || nix hash to-sri --type sha256 "$got" 2>/dev/null)"
  [[ "$got_sri" == "$new_sri" ]] \
    || err "hash mismatch: manifest says $new_sri, download is $got_sri"
  info "  download matches manifest hash."
fi

# Current pin (read from the UPDATE MARKER lines).
read_marker() {
  grep -oE "= \"[^\"]+\"; # UPDATE MARKER: $1\$" "$PACKAGE_NIX" \
    | grep -oE '"[^"]+"' | head -n1 | tr -d '"'
}
cur_version="$(read_marker version)"
cur_sha8="$(read_marker sha8)"
cur_sri="$(read_marker hash)"
[[ -n "$cur_version" && -n "$cur_sha8" && -n "$cur_sri" ]] \
  || err "could not read current UPDATE MARKER pins from package.nix"

if [[ "$cur_sha8" == "$new_sha8" && "$cur_version" == "$new_version" && "$cur_sri" == "$new_sri" ]]; then
  info "Already at $cur_version ($cur_sha8), nothing to do."
  exit 0
fi

info "Updating: $cur_version ($cur_sha8) -> $new_version ($new_sha8)"

# Rewrite only the marker lines (anchored on the marker comment so nothing
# else in the file can match), then refresh the "Last updated" header.
sed -i -E \
  -e "s|^(  version = )\"[^\"]+\"(; # UPDATE MARKER: version)$|\1\"${new_version}\"\2|" \
  -e "s|^(  sha8 = )\"[^\"]+\"(; # UPDATE MARKER: sha8)$|\1\"${new_sha8}\"\2|" \
  -e "s|^(    hash = )\"[^\"]+\"(; # UPDATE MARKER: hash)$|\1\"${new_sri}\"\2|" \
  "$PACKAGE_NIX"

today="$(date +%d%m%y)"
sed -i -E "s|^# Last updated: [0-9]+|# Last updated: ${today}|" "$PACKAGE_NIX"

# Confirm the sed actually took (guards against future marker drift).
grep -q "\"${new_version}\"; # UPDATE MARKER: version" "$PACKAGE_NIX" \
  || err "version marker did not update — check package.nix format"
grep -q "\"${new_sha8}\"; # UPDATE MARKER: sha8" "$PACKAGE_NIX" \
  || err "sha8 marker did not update — check package.nix format"
grep -q "\"${new_sri}\"; # UPDATE MARKER: hash" "$PACKAGE_NIX" \
  || err "hash marker did not update — check package.nix format"

info "Done. Review the diff before committing:"
info "  git -C $SCRIPT_DIR diff package.nix"
