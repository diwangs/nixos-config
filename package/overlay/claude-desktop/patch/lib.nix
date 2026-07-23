# Shared plumbing for the claude-desktop patch fragments (OpenRouter/3p + the
# Cowork-VM path patch).
#
# Each fragment under ./ (and ./3p) runs as a SELF-CONTAINED, order-independent
# step: it extracts app.asar into a fresh temp dir, applies its own
# substituteInPlace(s), and repacks. The patches touch disjoint minified
# anchors, so running each against a freshly-extracted tree (rather than
# chaining one shared extraction) makes them commute — add, remove, or reorder
# the imports in ../../../../nixos.nix without reasoning about interactions.
#
# The ONE load-bearing subtlety of the repack lives here, in `mkAsarPatch`, so
# it is written exactly once instead of copy-pasted into every fragment:
#
#   - Repack app.asar only; leave the existing app.asar.unpacked dir untouched.
#     The official build ships native addons (claude-native, node-pty) +
#     spawn-helper unpacked; a fresh --unpack with a different glob would drop
#     them.
#   - Match the unpack glob so the asar header keeps marking spawn-helper as
#     unpacked (else node-pty breaks).
#
# The official Anthropic build installs resources at
# $out/lib/claude-desktop/resources (same layout patrickjaja used), so asarRoot
# is unchanged from the claude-desktop-bin original this was adapted from.
#
# `mul31` also lives here so any fragment (e.g. 3p/thinking-flag.nix) can reach
# it via `helpers.mul31` without re-deriving it.
{ lib }:
let
  unpackGlob = "{**/*.node,**/spawn-helper}";

  # mul31: Java String.hashCode-style hash (seed 0, ×31 per char, kept as
  # uint32). Claude Desktop's growthbook seed map keys flags by this hash of the
  # flag name, not the name itself, so computing it lets a patch reference the
  # stable flag NAME instead of a magic number (stays correct as long as the
  # hash algorithm doesn't change). Verified against known pairs:
  # yukon_silver=574905726, yukon_silver_thinking=1658632017,
  # model_selector_enabled=4108768567.
  mul31 =
    name:
    builtins.foldl' (
      acc: c: lib.mod (acc * 31 + lib.strings.charToInt c) 4294967296
    ) 0 (lib.stringToCharacters name);
  # Since 1.24012.0 the main-process code no longer lives in one
  # .vite/build/index.js: Vite splits it into content-hashed chunks
  # (index.chunk-<hash>.js) whose names change every release, plus a tiny
  # index.js loader and a index.pre.js. A patch that hardcodes the filename
  # therefore silently drifts. `findChunk` resolves, at build time, the single
  # .vite/build file that carries a given fixed-string anchor, so patches key off
  # a stable code substring instead of the volatile chunk name. Emits a bash
  # command substitution; the caller assigns it to a var and substituteInPlaces
  # that path. (index.pre.js-resident anchors — e.g. the debug-port guard — don't
  # need this: that file's name is stable.)
  findChunk =
    locator:
    ''$(grep -rlF ${lib.escapeShellArg locator} "$work/contents/.vite/build")'';
in
{
  inherit unpackGlob mul31 findChunk;

  # mkAsarPatch: wrap a fragment's substituteInPlace body in its own
  # extract → patch → repack cycle. `body` is a bash snippet that mutates files
  # under "$work/contents" (e.g. substituteInPlace on .vite/build/index.js).
  # `label` is a human tag echoed into the build log so a drifted anchor is
  # traceable to its fragment.
  mkAsarPatch = { label, body }: ''
    echo "[claude-desktop patch] ${label}"
    asarRoot=$out/lib/claude-desktop/resources
    work=$(mktemp -d)
    asar extract "$asarRoot/app.asar" "$work/contents"

    ${body}

    asar pack "$work/contents" "$work/app.asar" --unpack "${unpackGlob}"
    cp -f "$work/app.asar" "$asarRoot/app.asar"
    rm -rf "$work"
  '';

  # mkLoosePatch: for files that live OUTSIDE app.asar. The official build ships
  # the Chat renderer as a loose bundle under resources/ion-dist/, so a patch
  # there mutates the file directly in the output tree — no extract/repack.
  # NOTE: consumers typically glob a hash-suffixed filename; a glob that matches
  # nothing makes the loop body silently no-op (not even a warning), so the
  # affected surface must be runtime-verified.
  mkLoosePatch = { label, body }: ''
    echo "[claude-desktop patch] ${label}"
    asarRoot=$out/lib/claude-desktop/resources
    ${body}
  '';
}
