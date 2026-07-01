#!/usr/bin/env bash
# Update the pinned Claude Desktop .deb (version + hash) in package.nix to the
# latest release in Anthropic's official apt repository
# (https://code.claude.com/docs/en/desktop-linux).
#
# The repo is a signed, pool-based apt repo. We read the amd64 Packages index,
# pick the highest Version stanza, and take its SHA256 straight from the index:
# the Release -> Packages -> .deb hash chain is what apt itself trusts, so we
# don't need to download the ~144 MB .deb just to hash it. The index hex sha256
# is converted to the SRI form fetchurl wants. (Set VERIFY_DOWNLOAD=1 to also
# fetch the .deb and confirm the hash end-to-end.)
#
# Usage:
#   ./update.sh                 # pick the latest version in the repo
#   ./update.sh 1.17377.1       # pin an explicit version (testing / rollback)
#
# Requires: curl, nix (nix hash convert), sed (GNU), sort -V, awk, grep.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PACKAGE_NIX="$SCRIPT_DIR/package.nix"

APT_BASE="https://downloads.claude.ai/claude-desktop/apt/stable"
PACKAGES_URL="$APT_BASE/dists/stable/main/binary-amd64/Packages"

err()  { printf 'error: %s\n' "$*" >&2; exit 1; }
info() { printf '==> %s\n' "$*"; }

for cmd in curl nix sed awk grep sort; do
  command -v "$cmd" >/dev/null || err "missing required command: $cmd"
done
[[ -f "$PACKAGE_NIX" ]] || err "package.nix not found at $PACKAGE_NIX"

info "Fetching apt Packages index..."
packages="$(curl -fsSL "$PACKAGES_URL")" || err "could not fetch $PACKAGES_URL"
[[ -n "$packages" ]] || err "empty Packages index"

# The index is RFC822 stanzas separated by blank lines. Emit one
# "Version<TAB>SHA256<TAB>Filename" line per claude-desktop stanza, then either
# pick the requested version or the highest by `sort -V` (all versions are
# plain dotted-numeric, so version sort is well-defined).
mapfile -t stanzas < <(
  awk -v RS='' '
    /(^|\n)Package: claude-desktop(\n|$)/ {
      ver=""; sha=""; fn="";
      n=split($0, lines, "\n");
      for (i=1; i<=n; i++) {
        if (lines[i] ~ /^Version: /)  { ver=lines[i]; sub(/^Version: /,  "", ver) }
        if (lines[i] ~ /^SHA256: /)   { sha=lines[i]; sub(/^SHA256: /,   "", sha) }
        if (lines[i] ~ /^Filename: /) { fn=lines[i];  sub(/^Filename: /, "", fn)  }
      }
      if (ver != "" && sha != "" && fn != "") printf "%s\t%s\t%s\n", ver, sha, fn
    }
  ' <<<"$packages"
)
[[ "${#stanzas[@]}" -gt 0 ]] || err "no usable claude-desktop stanza in index"

if [[ $# -ge 1 ]]; then
  want="$1"
  line="$(printf '%s\n' "${stanzas[@]}" | awk -F'\t' -v v="$want" '$1==v {print; exit}')"
  [[ -n "$line" ]] || err "version $want not found in repo"
else
  line="$(printf '%s\n' "${stanzas[@]}" | sort -V -r -t$'\t' -k1,1 | head -n1)"
fi

new_version="$(cut -f1 <<<"$line")"
hex_sha="$(cut -f2 <<<"$line")"
filename="$(cut -f3 <<<"$line")"
[[ "$hex_sha" =~ ^[0-9a-fA-F]{64}$ ]] || err "index SHA256 is not 64 hex chars: $hex_sha"

info "Latest in repo: $new_version"
info "  filename: $filename"

# hex sha256 (as apt records it) -> SRI (as fetchurl wants).
new_sri="$(nix hash convert --hash-algo sha256 --to sri "$hex_sha" 2>/dev/null \
  || nix hash to-sri --type sha256 "$hex_sha" 2>/dev/null)" \
  || err "nix hash convert failed"
[[ "$new_sri" == sha256-* ]] || err "unexpected SRI form: $new_sri"

# Optional end-to-end check: download the .deb and confirm it matches.
if [[ "${VERIFY_DOWNLOAD:-0}" == "1" ]]; then
  info "VERIFY_DOWNLOAD=1: prefetching .deb to confirm hash..."
  got="$(nix-prefetch-url --type sha256 "$APT_BASE/$filename")" \
    || err "prefetch failed"
  got_sri="$(nix hash convert --hash-algo sha256 --to sri "$got" 2>/dev/null \
    || nix hash to-sri --type sha256 "$got" 2>/dev/null)"
  [[ "$got_sri" == "$new_sri" ]] \
    || err "hash mismatch: index says $new_sri, download is $got_sri"
  info "  download matches index hash."
fi

# Current pin (read from the UPDATE MARKER lines).
cur_version="$(grep -oE 'version = "[^"]+"; # UPDATE MARKER: version' "$PACKAGE_NIX" \
  | grep -oE '"[^"]+"' | head -n1 | tr -d '"')"
cur_sri="$(grep -oE 'hash = "[^"]+"; # UPDATE MARKER: hash' "$PACKAGE_NIX" \
  | grep -oE '"[^"]+"' | head -n1 | tr -d '"')"
[[ -n "$cur_version" && -n "$cur_sri" ]] \
  || err "could not read current UPDATE MARKER pins from package.nix"

if [[ "$cur_version" == "$new_version" && "$cur_sri" == "$new_sri" ]]; then
  info "Already at $cur_version, nothing to do."
  exit 0
fi

info "Updating: $cur_version -> $new_version"

# Rewrite only the two marker lines (anchored on the marker comment so nothing
# else in the file can match), then refresh the "Last updated" header.
sed -i -E \
  -e "s|^(  version = )\"[^\"]+\"(; # UPDATE MARKER: version)$|\1\"${new_version}\"\2|" \
  -e "s|^(    hash = )\"[^\"]+\"(; # UPDATE MARKER: hash)$|\1\"${new_sri}\"\2|" \
  "$PACKAGE_NIX"

today="$(date +%d%m%y)"
sed -i -E "s|^# Last updated: [0-9]+|# Last updated: ${today}|" "$PACKAGE_NIX"

# Confirm the sed actually took (guards against future marker drift).
grep -q "\"${new_version}\"; # UPDATE MARKER: version" "$PACKAGE_NIX" \
  || err "version marker did not update — check package.nix format"
grep -q "\"${new_sri}\"; # UPDATE MARKER: hash" "$PACKAGE_NIX" \
  || err "hash marker did not update — check package.nix format"

info "Done. Review the diff before committing:"
info "  git -C $SCRIPT_DIR diff package.nix"
