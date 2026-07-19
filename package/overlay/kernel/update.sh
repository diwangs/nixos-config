#!/usr/bin/env bash
# Update the stable and LTS hardened kernel pins in kernel.nix to the latest
# releases from anthraxx/linux-hardened. Uses kernel.org's releases.json to
# decide which branch is "stable" and which is "longterm" — anthraxx also
# publishes regular-stable trees (e.g. 6.19.x) that are not the LTS.
#
# Usage:
#   ./update.sh                          # auto-detect via kernel.org
#   ./update.sh STABLE_MM LTS_MM         # e.g. ./update.sh 7.0 6.18
#
# Requires: curl, jq, nix-prefetch-url, sed (GNU).

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KERNEL_NIX="$SCRIPT_DIR/kernel.nix"
NIXOS_NIX="$SCRIPT_DIR/../../../nixos.nix"

err()  { printf 'error: %s\n' "$*" >&2; exit 1; }
info() { printf '==> %s\n' "$*"; }

# major.minor of a (possibly -hardenedN-suffixed) version, e.g.
#   7.0.12 -> 7.0   |   7.1 -> 7.1   |   7.1-hardened1 -> 7.1
# Plain "${v%.*}" is wrong for ".0" releases like 7.1 (gives "7").
mm_of() { echo "${1%%-*}" | awk -F. '{print $1"."$2}'; }

for cmd in curl jq nix-prefetch-url sed awk grep; do
  command -v "$cmd" >/dev/null || err "missing required command: $cmd"
done
[[ -f "$KERNEL_NIX" ]] || err "kernel.nix not found at $KERNEL_NIX"
[[ -f "$NIXOS_NIX" ]] || err "nixos.nix not found at $NIXOS_NIX"

info "Fetching releases from anthraxx/linux-hardened..."
all_tags=$(
  curl -fsSL "https://api.github.com/repos/anthraxx/linux-hardened/releases?per_page=100" \
    | jq -r '.[].tag_name' \
    | sed 's/^v//' \
    | grep -E '^[0-9]+\.[0-9]+(\.[0-9]+)?-hardened[0-9]+$' \
    | sort -V -r
)
[[ -n "$all_tags" ]] || err "no usable release tags returned"

# Pick the newest anthraxx tag whose major.minor matches $1 (e.g. "6.18").
# Tags may be two- or three-component (7.1-hardened1 vs 7.0.12-hardened1), so
# derive major.minor with mm_of rather than a fixed field split.
pick_latest_in_branch() {
  local want="$1" tag
  while IFS= read -r tag; do
    [[ "$(mm_of "$tag")" == "$want" ]] && { echo "$tag"; return; }
  done <<< "$all_tags"
}

if [[ $# -ge 2 ]]; then
  stable_mm="$1"
  lts_mm="$2"
else
  info "Resolving branch designations from kernel.org..."
  kernel_org=$(curl -fsSL https://www.kernel.org/releases.json)
  stable_full=$(echo "$kernel_org" | jq -r '.latest_stable.version')
  # Highest-numbered longterm entry = newest LTS line.
  lts_full=$(echo "$kernel_org" \
    | jq -r '.releases[] | select(.moniker=="longterm") | .version' \
    | sort -V -r | head -n1)
  [[ -n "$stable_full" && -n "$lts_full" ]] \
    || err "could not parse kernel.org release metadata"
  stable_mm="$(mm_of "$stable_full")"
  lts_mm="$(mm_of "$lts_full")"
fi

latest_stable=$(pick_latest_in_branch "$stable_mm")
latest_lts=$(pick_latest_in_branch "$lts_mm")
[[ -n "$latest_stable" ]] || err "no anthraxx release found on stable branch $stable_mm"
[[ -n "$latest_lts"    ]] || err "no anthraxx release found on LTS branch $lts_mm"

info "Stable branch $stable_mm -> $latest_stable"
info "LTS    branch $lts_mm -> $latest_lts"

prefetch_kernel() {
  local version="$1" major="${1%%.*}"
  nix-prefetch-url --type sha256 \
    "mirror://kernel/linux/kernel/v${major}.x/linux-${version}.tar.xz" 2>/dev/null
}
prefetch_patch() {
  local full="$1"
  nix-prefetch-url --type sha256 --name "linux-hardened-v${full}.patch" \
    "https://github.com/anthraxx/linux-hardened/releases/download/v${full}/linux-hardened-v${full}.patch" \
    2>/dev/null
}

# Rewrite a single overlay block in kernel.nix.
#   $1 kind            "stable" | "lts" (just for logging)
#   $2 marker_regex    grep -E pattern that uniquely identifies the block's comment line
#   $3 new_full        e.g. "7.0.11-hardened1"
#   $4 new_kernel_sha
#   $5 new_patch_sha
update_block() {
  local kind="$1" marker_re="$2" new_full="$3" new_kernel_sha="$4" new_patch_sha="$5"

  local new_version="${new_full%-hardened*}"
  local new_extra="-${new_full#*-}"                          # "-hardened1"
  local new_mm; new_mm="$(mm_of "$new_version")"             # "7.0" / "7.1"
  local new_ver_under="${new_version//./_}"                  # "7_0_10" / "7_1"

  local start end block_indent
  start=$(grep -nE "$marker_re" "$KERNEL_NIX" | head -n1 | cut -d: -f1)
  [[ -n "$start" ]] || err "could not locate $kind block marker (/$marker_re/)"
  block_indent=$(sed -n "$((start + 1))s/[^[:space:]].*$//p" "$KERNEL_NIX")
  end=$(awk -v s="$start" -v closing="${block_indent});" \
    'NR >= s && $0 == closing { print NR; exit }' "$KERNEL_NIX")
  [[ -n "$end" ]] || err "could not locate end of $kind block"

  local block cur_version cur_extra cur_full cur_mm cur_ver_under
  block=$(sed -n "${start},${end}p" "$KERNEL_NIX")
  cur_version=$(echo "$block" | grep -oE 'version *= *"[0-9]+\.[0-9]+(\.[0-9]+)?"' \
                | head -n1 | grep -oE '[0-9]+\.[0-9]+(\.[0-9]+)?')
  cur_extra=$(echo "$block" | grep -oE 'extra *= *"-hardened[0-9]+"' \
              | head -n1 | grep -oE -- '-hardened[0-9]+')
  [[ -n "$cur_version" && -n "$cur_extra" ]] \
    || err "could not parse current version/extra in $kind block"
  cur_full="${cur_version}${cur_extra}"
  cur_mm="$(mm_of "$cur_version")"
  cur_ver_under="${cur_version//./_}"

  local cur_kernel_sha cur_patch_sha sha_lines
  local -a shas
  sha_lines=$(echo "$block" | grep -oE 'sha256 *= *"[^"]+"' \
              | sed -E 's/.*"([^"]+)"$/\1/')
  mapfile -t shas <<< "$sha_lines"
  cur_kernel_sha="${shas[0]:-}"
  cur_patch_sha="${shas[1]:-}"
  [[ -n "$cur_kernel_sha" && -n "$cur_patch_sha" ]] \
    || err "could not parse current sha256s in $kind block"

  if [[ "$cur_full" == "$new_full" \
        && "$cur_kernel_sha" == "$new_kernel_sha" \
        && "$cur_patch_sha"  == "$new_patch_sha" ]]; then
    info "$kind already at $cur_full, skipping"
    return
  fi

  info "Updating $kind (lines $start-$end): $cur_full -> $new_full"

  sed -i "${start},${end} {
    s|linuxKernel_${cur_ver_under}_hardenedOverlay|linuxKernel_${new_ver_under}_hardenedOverlay|g
    s|\"${cur_mm}\" = {|\"${new_mm}\" = {|g
    s|version *= *\"${cur_version}\"|version = \"${new_version}\"|g
    s|\"${cur_extra}\"|\"${new_extra}\"|g
    s|${cur_full}|${new_full}|g
    s|\"${cur_kernel_sha}\"|\"${new_kernel_sha}\"|g
    s|\"${cur_patch_sha}\"|\"${new_patch_sha}\"|g
  }" "$KERNEL_NIX"
}

update_stable_overlay_reference() {
  local version="${1%-hardened*}"
  local version_under="${version//./_}"
  local pattern='^[[:space:]]*\.linuxKernel_[0-9_]+_hardenedOverlay$'

  grep -qE "$pattern" "$NIXOS_NIX" \
    || err "could not locate stable kernel overlay reference in $NIXOS_NIX"
  sed -i -E "s|^([[:space:]]*)\.linuxKernel_[0-9_]+_hardenedOverlay$|\\1.linuxKernel_${version_under}_hardenedOverlay|" "$NIXOS_NIX"
}

info "Hashing stable ($latest_stable)..."
stable_version="${latest_stable%-hardened*}"
stable_kernel_sha=$(prefetch_kernel "$stable_version")
stable_patch_sha=$(prefetch_patch  "$latest_stable")
[[ -n "$stable_kernel_sha" && -n "$stable_patch_sha" ]] \
  || err "failed to hash stable kernel or patch"

info "Hashing LTS ($latest_lts)..."
lts_version="${latest_lts%-hardened*}"
lts_kernel_sha=$(prefetch_kernel "$lts_version")
lts_patch_sha=$(prefetch_patch  "$latest_lts")
[[ -n "$lts_kernel_sha" && -n "$lts_patch_sha" ]] \
  || err "failed to hash LTS kernel or patch"

update_block stable '# Latest stable from anthraxx' \
  "$latest_stable" "$stable_kernel_sha" "$stable_patch_sha"
update_stable_overlay_reference "$latest_stable"

update_block lts '# Backup: Latest LTS' \
  "$latest_lts" "$lts_kernel_sha" "$lts_patch_sha"

# Refresh the "Last updated: ddmmyy" header.
today=$(date +%d%m%y)
sed -i -E "s|^# Last updated: [0-9]+|# Last updated: ${today}|" "$KERNEL_NIX"

info "Done. Review the diff before committing."
