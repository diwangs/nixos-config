#!/usr/bin/env bash
# Pull the chatgpt package files from nixpkgs PR #551713 into this overlay so
# `pkgs.chatgpt` tracks the upstream draft Linux packaging.
#
# The files are fetched at the PR head commit and rewritten in place only when
# that head moves (tracked in ./.pinned-rev). Re-run this script whenever the
# PR receives new commits.
#
# Requires: gh (authenticated), curl, git.

set -euo pipefail

PR=551713
UPSTREAM_REPO="NixOS/nixpkgs"
PKG_PATH="pkgs/by-name/ch/chatgpt"
FILES=(package.nix source.json launcher.nix update.sh)
OBSOLETE_FILES=(source.nix)

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REV_FILE="$SCRIPT_DIR/.pinned-rev"

err()  { printf 'error: %s\n' "$*" >&2; exit 1; }
info() { printf '==> %s\n' "$*"; }

for cmd in gh curl git; do
  command -v "$cmd" >/dev/null || err "missing required command: $cmd"
done

info "Querying PR #$PR head..."
read -r owner repo branch head <<<"$(
  gh pr view "$PR" --repo "$UPSTREAM_REPO" \
    --json headRepositoryOwner,headRepository,headRefName,headRefOid \
    --jq '[.headRepositoryOwner.login, .headRepository.name, .headRefName, .headRefOid] | @tsv'
)"
[[ -n "${head:-}" ]] || err "could not resolve PR head commit (is gh authenticated?)"
info "head: $owner/$repo@$branch ($head)"

pinned=""
[[ -f "$REV_FILE" ]] && pinned="$(cat "$REV_FILE")"

if [[ "$pinned" == "$head" ]]; then
  info "Already at $head — no new commit, nothing to pull."
  exit 0
fi

info "Head moved (${pinned:-<none>} -> $head); pulling $PKG_PATH..."
staging_dir="$(mktemp -d)"
trap 'rm -rf -- "$staging_dir"' EXIT

for f in "${FILES[@]}"; do
  url="https://raw.githubusercontent.com/$owner/$repo/$head/$PKG_PATH/$f"
  info "fetch $f"
  curl -fsSL "$url" -o "$staging_dir/$f" || err "failed to fetch $f from $url"
done

for f in "${FILES[@]}"; do
  mv -- "$staging_dir/$f" "$SCRIPT_DIR/$f"
done
rm -f -- "${OBSOLETE_FILES[@]/#/$SCRIPT_DIR/}"
chmod +x "$SCRIPT_DIR/update.sh"

printf '%s\n' "$head" >"$REV_FILE"

# Nix only reads git-tracked files, so intent-to-add anything newly pulled.
git -C "$SCRIPT_DIR" add -N -- "${FILES[@]}" .pinned-rev 2>/dev/null || true

info "Pulled PR #$PR @ $head. Review the diff, then \`nix flake check\`."
