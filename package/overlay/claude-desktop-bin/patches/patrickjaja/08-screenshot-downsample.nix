# Eighth patch: fix Computer Use click SCALING on GNOME/Wayland.
#
# The coordinate round-trip (screenshot -> LLM -> click):
#   1. executor captures the screen at NATIVE resolution (e.g. 2560x1440)
#   2. the image is sent to the model, but the Anthropic API DOWNSAMPLES it in
#      transit to its vision token budget — see the per-model tiers in
#      maintenance note 2. For our model (Sonnet-tier: long edge <=1568 AND
#      <=1568 visual 28x28 patches, ~1.23Mpx), a 2560x1440 capture -> ~1430x804.
#   3. the model picks a click coordinate in that DOWNSAMPLED image space
#   4. the executor must map that coordinate back to NATIVE screen space to click
#
# macOS does this correctly: its native executor resizes the screenshot itself
# and reports the resized dimensions alongside it, so the image the model sees
# and the scale factor used to map clicks back are always the same transform —
# capture-space and click-space stay in sync by construction.
#
# patrickjaja's Linux gap: the executor sends the NATIVE image and maps clicks
# with `__txC(c) = c + monitorOrigin` — origin only, no scale. It never learns
# that the API shrank the image, so it treats the model's downsampled-space
# coordinate as native-space. Result: clicks undershoot by the downsample ratio
# (~1.79x on a 2560 display); they land at `aim + origin` instead of the target.
#
# This patch restores the macOS discipline — the executor owns the downsample
# and reports its scale — with two edits:
#   (1) executor `screenshot()` downsamples the image to the API budget itself
#       (via `magick`) and records `globalThis.__cuScale = nativeW/resizedW`
#       (1.0 if no resize). The model now sees the exact size we scaled for.
#   (2) `__txC(c)` multiplies the model coordinate by `__cuScale` BEFORE adding
#       the monitor origin, mapping downsampled-space back to native screen space.
#
# Maintenance notes (1) — escaping/tooling: use `magick` (nixpkgs IM7's
# `convert` silently no-ops -resize); the `>` in `-resize '1568x1568>'` must be
# single-quoted for /bin/sh -c (emitted as \x27...\x27). Both anchors are
# single-line & unique; `node --check` the extracted index.js after building.
#
# Maintenance notes (2) — the downsample target is MODEL-TIER-DEPENDENT, and our
# `1568x1568>` + `@1150000>` values are the STANDARD tier. Per Anthropic's vision
# docs the API enforces two caps (long-edge AND visual-token, where 1 token = a
# 28x28 patch), and the tier depends on the served model:
#   - Standard      (Sonnet 4.6, Opus 4.6, Haiku, ...): 1568 px long edge / 1568
#     patches (~1.23Mpx)  <- what this patch targets
#   - High-resolution (Fable 5, Mythos 5, Opus 4.8, Opus 4.7): 2576 px / 4784
#     patches (~3.75Mpx)
# This box runs Claude Desktop in 3p mode against OpenRouter's
# `anthropic/claude-sonnet-4.6` (standard tier), so the hardcoded standard values
# are correct TODAY. If the desktop app is ever pointed at an Opus 4.7/4.8 model,
# the API would downsample to the high-res tier instead and these fixed numbers
# would re-introduce click drift — bump the resize to `2576x2576>` + `@3750000>`
# (or, more robustly, derive the budget from the served model's tier). Docs:
# https://platform.claude.com/docs/en/build-with-claude/vision (Resolution and
# token cost) and .../vision-coordinates (How Claude resizes and pads images).
#
# Standalone overlay: import after ./base.nix; order vs other patches is
# irrelevant (per-fragment extract/repack — see ../base.nix).
final: prev:
let
  helpers = import ../../lib.nix { inherit (final) lib; };
in
{
  claude-desktop = prev.claude-desktop.overrideAttrs (old: {
    postInstall = (old.postInstall or "") + "\n" + helpers.mkAsarPatch {
      label = "08 computer-use click scaling (downsample + __cuScale)";
      body = ''
        # (1) compact executor screenshot(): downsample to API budget + publish
        # __cuScale. Anchored on the unique single-line opener `async screenshot(opts){`
        # (the framework variant has a space: `screenshot(opts) {`), injecting an
        # early-returning body. The original `var mon...return{base64:b64};` that
        # follows becomes dead code (unreachable-after-return is valid JS); we use
        # our own _mon/_b64 names so there's no redeclaration conflict.
        substituteInPlace "$work/contents/.vite/build/index.js" \
          --replace-warn \
            'async screenshot(opts){' \
            'async screenshot(opts){var _mon=_findMon(opts&&opts.displayId),_b64=await _screenshotMon(_mon);globalThis.__cuScale=1;try{if(_hasCmd("magick")&&_hasCmd("identify")){var _nb=Buffer.from(_b64,"base64"),_nw=_nb.length>24?_nb.readUInt32BE(16):0;var _i=_path.join(_os.tmpdir(),"cu-ds-"+Date.now()+"-i.png"),_o=_path.join(_os.tmpdir(),"cu-ds-"+Date.now()+"-o.png");_fs.writeFileSync(_i,_nb);_cp.execSync("magick "+JSON.stringify(_i)+" -resize \x271568x1568>\x27 -resize \x27@1150000>\x27 "+JSON.stringify(_o),{timeout:10000});var _ob=_fs.readFileSync(_o),_rw=_ob.length>24?_ob.readUInt32BE(16):0;if(_rw>0&&_nw>0&&_rw<_nw){_b64=_ob.toString("base64");globalThis.__cuScale=_nw/_rw}try{_fs.unlinkSync(_i)}catch(e){}try{_fs.unlinkSync(_o)}catch(e){}}}catch(e){console.warn("[claude-cu] screenshot downsample failed, scale=1: "+e.message)}return{base64:_b64};'

        # (2) __txC: apply __cuScale to the model coord before adding the monitor origin.
        substituteInPlace "$work/contents/.vite/build/index.js" \
          --replace-warn \
            'function __txC(c){var o=globalThis.__cuActiveOrigin;return[(c[0]||0)+(o?o.x:0),(c[1]||0)+(o?o.y:0)]}' \
            'function __txC(c){var o=globalThis.__cuActiveOrigin,s=globalThis.__cuScale||1;return[Math.round((c[0]||0)*s)+(o?o.x:0),Math.round((c[1]||0)*s)+(o?o.y:0)]}'
      '';
    };
  });
}
