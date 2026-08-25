#!/usr/bin/env bash
# Update the stable and LTS hardened kernel pins in kernel.nix to the latest
# releases from anthraxx/linux-hardened. The stable branch is capped at the
# newest kernel branch exposed by the pinned nixpkgs; kernel.org's releases.json
# is used to select the newest longterm branch. Anthraxx also publishes
# regular-stable trees (e.g. 6.19.x) that are not the LTS.
#
# Usage:
#   ./update.sh                          # stable from nixpkgs, LTS from kernel.org
#   ./update.sh STABLE_MM LTS_MM         # e.g. ./update.sh 7.0 6.18
#
# Requires: curl, jq, nix, nix-prefetch-url, sed (GNU), awk, grep, sort,
# timeout (GNU).

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KERNEL_NIX="$SCRIPT_DIR/kernel.nix"
NIXOS_NIX="$SCRIPT_DIR/../../../nixos.nix"
FLAKE_ROOT="$SCRIPT_DIR/../../.."

err()  { printf 'error: %s\n' "$*" >&2; exit 1; }
info() { printf '==> %s\n' "$*"; }

# major.minor of a (possibly -hardenedN-suffixed) version, e.g.
#   7.0.12 -> 7.0   |   7.1 -> 7.1   |   7.1-hardened1 -> 7.1
# Plain "${v%.*}" is wrong for ".0" releases like 7.1 (gives "7").
mm_of() { echo "${1%%-*}" | awk -F. '{print $1"."$2}'; }

for cmd in curl jq nix nix-prefetch-url sed awk grep sort timeout; do
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

# Determine the newest mainline kernel branch actually exposed by the pinned
# nixpkgs. Use the first NixOS configuration only to reach its overlaid `pkgs`;
# all configurations in this flake share the same nixpkgs input.
info "Resolving the newest kernel branch available in pinned nixpkgs..."
nixos_config=$(
  nix eval --json "$FLAKE_ROOT#nixosConfigurations" --apply builtins.attrNames \
    | jq -r 'first // empty'
)
[[ -n "$nixos_config" ]] || err "flake has no NixOS configuration to inspect"

nixpkgs_stable_mm=$(
  nix eval --json \
    "$FLAKE_ROOT#nixosConfigurations.${nixos_config}.pkgs.linuxKernel.kernels" \
    --apply builtins.attrNames \
    | jq -r '.[] | select(test("^linux_[0-9]+_[0-9]+$")) | sub("^linux_"; "") | gsub("_"; ".")' \
    | sort -V \
    | tail -n1
)
[[ -n "$nixpkgs_stable_mm" ]] \
  || err "could not determine the newest kernel branch from pinned nixpkgs"
info "Pinned nixpkgs supports kernels through $nixpkgs_stable_mm"

version_gt() {
  [[ "$1" != "$2" && "$(printf '%s\n' "$1" "$2" | sort -V | tail -n1)" == "$1" ]]
}

if [[ $# -ge 2 ]]; then
  stable_mm="$1"
  lts_mm="$2"
  if version_gt "$stable_mm" "$nixpkgs_stable_mm"; then
    info "Capping requested stable branch $stable_mm at nixpkgs branch $nixpkgs_stable_mm"
    stable_mm="$nixpkgs_stable_mm"
  fi
else
  stable_mm="$nixpkgs_stable_mm"
  info "Resolving the longterm branch designation from kernel.org..."
  kernel_org=$(curl -fsSL https://www.kernel.org/releases.json)
  # Highest-numbered longterm entry = newest LTS line.
  lts_full=$(echo "$kernel_org" \
    | jq -r '.releases[] | select(.moniker=="longterm") | .version' \
    | sort -V -r | head -n1)
  [[ -n "$lts_full" ]] \
    || err "could not parse kernel.org release metadata"
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
  timeout --foreground 10m nix-prefetch-url --type sha256 \
    "mirror://kernel/linux/kernel/v${major}.x/linux-${version}.tar.xz"
}
prefetch_patch() {
  local full="$1"
  timeout --foreground 10m nix-prefetch-url --type sha256 \
    --name "linux-hardened-v${full}.patch" \
    "https://github.com/anthraxx/linux-hardened/releases/download/v${full}/linux-hardened-v${full}.patch"
}

# Print the currently pinned full version, kernel hash, and patch hash for the
# block identified by $2, one value per line. This lets unchanged branches
# avoid re-downloading a kernel tarball merely to rediscover the same hashes.
read_current_pin() {
  local kind="$1" marker_re="$2" start end block_indent block
  local version extra sha_lines
  local -a shas

  start=$(grep -nE "$marker_re" "$KERNEL_NIX" | head -n1 | cut -d: -f1)
  [[ -n "$start" ]] || err "could not locate $kind block marker (/$marker_re/)"
  block_indent=$(sed -n "$((start + 1))s/[^[:space:]].*$//p" "$KERNEL_NIX")
  end=$(awk -v s="$start" -v closing="${block_indent});" \
    'NR >= s && $0 == closing { print NR; exit }' "$KERNEL_NIX")
  [[ -n "$end" ]] || err "could not locate end of $kind block"

  block=$(sed -n "${start},${end}p" "$KERNEL_NIX")
  version=$(echo "$block" | grep -oE 'version *= *"[0-9]+\.[0-9]+(\.[0-9]+)?"' \
            | head -n1 | grep -oE '[0-9]+\.[0-9]+(\.[0-9]+)?')
  extra=$(echo "$block" | grep -oE 'extra *= *"-hardened[0-9]+"' \
          | head -n1 | grep -oE -- '-hardened[0-9]+')
  sha_lines=$(echo "$block" | grep -oE 'sha256 *= *"[^"]+"' \
              | sed -E 's/.*"([^"]+)"$/\1/')
  mapfile -t shas <<< "$sha_lines"

  [[ -n "$version" && -n "$extra" && -n "${shas[0]:-}" && -n "${shas[1]:-}" ]] \
    || err "could not parse current version or hashes in $kind block"
  printf '%s\n%s\n%s\n' "${version}${extra}" "${shas[0]}" "${shas[1]}"
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
  local branch branch_under overlay_pattern kernel_pattern
  branch=$(mm_of "$version")
  branch_under="${branch//./_}"
  overlay_pattern='^[[:space:]]*\.linuxKernel_[0-9_]+_hardenedOverlay$'
  kernel_pattern='pkgs\.linuxKernel\.kernels\.linux_[0-9]+_[0-9]+'

  grep -qE "$overlay_pattern" "$NIXOS_NIX" \
    || err "could not locate stable kernel overlay reference in $NIXOS_NIX"
  sed -i -E "s|^([[:space:]]*)\.linuxKernel_[0-9_]+_hardenedOverlay$|\\1.linuxKernel_${version_under}_hardenedOverlay|" "$NIXOS_NIX"

  grep -qE "$kernel_pattern" "$NIXOS_NIX" \
    || err "could not locate stable base kernel reference in $NIXOS_NIX"
  sed -i -E "s|${kernel_pattern}|pkgs.linuxKernel.kernels.linux_${branch_under}|" "$NIXOS_NIX"
}

stable_pin=$(read_current_pin stable '# Latest stable from anthraxx')
mapfile -t stable_current <<< "$stable_pin"
if [[ "${stable_current[0]}" == "$latest_stable" ]]; then
  info "Stable $latest_stable is already pinned; reusing existing hashes"
  stable_kernel_sha="${stable_current[1]}"
  stable_patch_sha="${stable_current[2]}"
else
  stable_version="${latest_stable%-hardened*}"
  info "Prefetching stable kernel source ($latest_stable)..."
  stable_kernel_sha=$(prefetch_kernel "$stable_version") \
    || err "failed to fetch or hash stable kernel source"
  info "Prefetching stable hardened patch ($latest_stable)..."
  stable_patch_sha=$(prefetch_patch "$latest_stable") \
    || err "failed to fetch or hash stable hardened patch"
fi

lts_pin=$(read_current_pin lts '# Backup: Latest LTS')
mapfile -t lts_current <<< "$lts_pin"
if [[ "${lts_current[0]}" == "$latest_lts" ]]; then
  info "LTS $latest_lts is already pinned; reusing existing hashes"
  lts_kernel_sha="${lts_current[1]}"
  lts_patch_sha="${lts_current[2]}"
else
  lts_version="${latest_lts%-hardened*}"
  info "Prefetching LTS kernel source ($latest_lts)..."
  lts_kernel_sha=$(prefetch_kernel "$lts_version") \
    || err "failed to fetch or hash LTS kernel source"
  info "Prefetching LTS hardened patch ($latest_lts)..."
  lts_patch_sha=$(prefetch_patch "$latest_lts") \
    || err "failed to fetch or hash LTS hardened patch"
fi

update_block stable '# Latest stable from anthraxx' \
  "$latest_stable" "$stable_kernel_sha" "$stable_patch_sha"
update_stable_overlay_reference "$latest_stable"

update_block lts '# Backup: Latest LTS' \
  "$latest_lts" "$lts_kernel_sha" "$lts_patch_sha"

# Refresh the "Last updated: ddmmyy" header.
today=$(date +%d%m%y)
sed -i -E "s|^# Last updated: [0-9]+|# Last updated: ${today}|" "$KERNEL_NIX"

info "Done. Review the diff before committing."
