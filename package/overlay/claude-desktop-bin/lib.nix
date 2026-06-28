# Shared plumbing for the per-patch claude-desktop fragments.
#
# Each fragment under ./patches runs as a SELF-CONTAINED, order-independent
# step: it extracts app.asar into a fresh temp dir, applies its own
# substituteInPlace(s), and repacks. The patches touch disjoint minified
# anchors, so running each against a freshly-extracted tree (rather than
# chaining one shared extraction) makes them commute — you can add, remove, or
# reorder fragments without reasoning about interactions.
#
# The ONE load-bearing subtlety of the repack lives here, in `mkAsarPatch`, so
# it is written exactly once instead of copy-pasted into every fragment:
#
#   - Repack app.asar only; leave the existing app.asar.unpacked dir untouched.
#     The build adds files AFTER the original pack (Linux node-pty +
#     spawn-helper, claude-native stub, cowork daemon) that a fresh --unpack
#     would drop.
#   - Match upstream's unpack glob so the asar header keeps marking spawn-helper
#     as unpacked (else node-pty breaks).
#
# patrickjaja installs to resources/ directly (no electron/ segment).
#
# `mul31` also lives here so any individual patch overlay can reach it via
# `helpers.mul31` without re-deriving it.
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
  mul31 = name: builtins.foldl'
    (acc: c: lib.mod (acc * 31 + lib.strings.charToInt c) 4294967296)
    0
    (lib.stringToCharacters name);
in
{
  inherit unpackGlob mul31;

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

  # mkLoosePatch: for files that live OUTSIDE app.asar (patrickjaja ships the
  # ion bundle as a loose file under resources/locales/ion-dist). No
  # extract/repack — just mutate the file in place in the output tree.
  mkLoosePatch = { label, body }: ''
    echo "[claude-desktop patch] ${label}"
    asarRoot=$out/lib/claude-desktop/resources
    ${body}
  '';
}
