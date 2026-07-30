#!/usr/bin/env bash
# Pull the claude-desktop package files from nixpkgs PR #537215 into this
# overlay, so the dogfooded `pkgs.claude-desktop` tracks the upstream draft
# packaging.
#
# The PR (https://github.com/NixOS/nixpkgs/pull/537215) inits claude-desktop in
# nixpkgs; diwangs is a co-maintainer. ../claude-desktop-draft/overlay.nix
# callPackages the PR's package.nix verbatim as `pkgs.claude-desktop`, replacing
# the local ../claude-desktop base overlay (kept on disk but disabled).
#
# pull.sh fetches the PR head's package.nix + update.sh at the current head
# commit and rewrites the vendored copies IN PLACE, but only when the head has
# moved since the last pull (tracked in ./.pinned-rev). Re-run it whenever the
# PR gets new commits; the fetch follows the PR's head repo/branch, so it keeps
# working even if the contributor force-pushes or renames the branch.
#
# Requires: gh (authenticated), curl, git.

set -euo pipefail

PR=537215
UPSTREAM_REPO="NixOS/nixpkgs"
PKG_PATH="pkgs/by-name/cl/claude-desktop"
FILES=(package.nix update.sh)

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
for f in "${FILES[@]}"; do
  url="https://raw.githubusercontent.com/$owner/$repo/$head/$PKG_PATH/$f"
  info "fetch $f"
  curl -fsSL "$url" -o "$SCRIPT_DIR/$f" || err "failed to fetch $f from $url"
done
chmod +x "$SCRIPT_DIR/update.sh"

printf '%s\n' "$head" >"$REV_FILE"

# Nix only reads git-tracked files, so intent-to-add anything newly pulled.
git -C "$SCRIPT_DIR" add -N -- "${FILES[@]}" .pinned-rev 2>/dev/null || true

info "Pulled PR #$PR @ $head. Review the diff, then \`nix flake check\`."
