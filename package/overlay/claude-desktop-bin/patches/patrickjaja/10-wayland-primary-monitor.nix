# Tenth patch: fix Computer Use SCREENSHOT (wrong monitor/aspect) and CLICK
# (lands on wrong spot/monitor) on native-Wayland GNOME with a multi-monitor,
# mixed-orientation layout. Replaces the XWayland workaround (old patches 06+09,
# now deleted): we run the app under native Wayland (--ozone-platform=wayland)
# and keep ydotool for input.
#
# This box's layout (Mutter GetCurrentState ground truth):
#   DP-7 landscape 2560x1440 at logical origin (1080,480)  <- Mutter PRIMARY
#   DP-8 portrait  1080x1920 at logical origin (0,0)
#   desktop bbox 3640x1920, bottoms aligned.
#
# TWO independent bugs, both rooted in "which monitor is primary":
#
#   (A) SCREENSHOT — wrong monitor / wrong aspect. The CU screenshot handler
#       picks the default display from the executor's `isPrimary` flag, which
#       `_getMonitors` copies from Electron's `screen.getPrimaryDisplay()`. Under
#       native Wayland, Electron MIS-REPORTS the primary as the portrait DP-8
#       (verified live: getPrimaryDisplay().id = the 1080x1920 @ (0,0) panel;
#       getCursorScreenPoint() also always returns (0,0) — Electron's Wayland
#       display/cursor reporting is broken here). So a default screenshot
#       captures the PORTRAIT monitor (e.g. 804x1430 downsampled, aspect 0.56/
#       0.75 — not the landscape 1.78) and sets __cuActiveOrigin={0,0}. The model
#       sees the wrong screen at the wrong aspect.
#
#   (B) CLICK — double origin offset (+ a non-determinism). ydotool's
#       `mousemove --absolute X Y` axis is MONITOR-LOCAL to the Mutter-PRIMARY
#       monitor (DP-7): it lands at desktop (X+1080, Y+480), CLAMPED to DP-7, and
#       cannot reach the portrait monitor at all (measured: 0 mismatches over 20
#       targets for `desktop = raw + (1080,480)`; negative/out-of-range args are
#       ignored or clamp). But the executor already feeds ydotool DESKTOP-
#       ABSOLUTE coords (`__txC(c) = c*__cuScale + __cuActiveOrigin`), so ydotool
#       adds the primary origin a SECOND time → clicks land at target+(1080,480),
#       i.e. down-right of the mark ("off to upper-left" from the model's view).
#       Verified: ex.moveMouse(2360,1200) → pointer (3440,1680). Separately, the
#       executor's `abs(0,0); sleep; relative(x,y)` idiom is genuinely flaky (the
#       first move after idle drops the origin: 1/5 mismatch); a single pure
#       `--absolute` move is deterministic (0/20).
#
# Both reduce to one authoritative fact: the Mutter-PRIMARY logical-monitor
# origin (1080,480) — which is exactly the monitor ydotool can address, and the
# only one CU can reliably drive. ydotool's absolute axis cannot reach DP-8, so
# we lock CU to DP-7 (see AskUser decision in the task) and use that origin both
# to pick the capture monitor and to undo ydotool's built-in offset.
#
# FIX — three edits to the JS executor (the active CU path on Linux/GNOME is
# `h8e.handleToolCall` → globalThis.__linuxExecutor, NOT the dead Rust/claude-
# native path: @ant/claude-native ships EMPTY on Linux and kwin-portal-bridge is
# KDE-only):
#
#   (1) Inject `__cuGetPrimaryOrigin()` — queries Mutter DisplayConfig
#       (org.gnome.Mutter.DisplayConfig.GetCurrentState) for the primary logical
#       monitor's origin and caches it. This is a STANDARD unprivileged read API
#       (the same one gnome-control-center's Displays panel uses) — it does NOT
#       require Mutter `unsafe_mode`. `gdbus` is already on the app PATH (glib bin
#       comes in via the portal-screenshot deps in base.nix). On any failure it
#       falls back to {0,0} (degrades to the pre-patch behavior, logged).
#
#   (2) `_getMonitors`: set the executor's `primaryId` to the Electron display
#       whose bounds ORIGIN matches the Mutter primary (Electron's per-display
#       bounds ARE correct — only its isPrimary flag is wrong; both report DP-7
#       at (1080,480)). Falls back to Electron's getPrimaryDisplay() if no match.
#       This one change fixes (A): the default screenshot now captures DP-7 and
#       __cuActiveOrigin becomes (1080,480).
#
#   (3) `_moveMouse` and `drag`: replace the flaky `abs(0,0); sleep; relative`
#       idiom with a single pure `ydotool mousemove --absolute (x-originX)
#       (y-originY)`, subtracting the Mutter-primary origin so ydotool's internal
#       re-add cancels it. Fixes (B): clicks land exactly on target. (scroll uses
#       _moveMouse + relative wheel deltas — covered transitively; wheel deltas
#       need no offset.)
#
# Round-trip after the fix (verified end-to-end against `global.get_pointer()`):
# capture DP-7 (2560x1440) → patch 08 downsamples + sets __cuScale → model picks
# coord → __txC = coord*scale + (1080,480) [desktop-abs] → ydotool fed
# (desktop-abs - (1080,480)) [monitor-local] → ydotool re-adds (1080,480) →
# lands on target. The __txC add and the ydotool subtract cancel for DP-7, and
# __cuActiveOrigin stays correct for cursor_position reporting.
#
# Standalone overlay: import after ./base.nix; order vs other patches is
# irrelevant (per-fragment extract/repack — see ../base.nix). Composes with 08
# (downsample/__cuScale) and 05 (CU enable); touches disjoint anchors.
final: prev:
let
  helpers = import ../../lib.nix { inherit (final) lib; };
in
{
  claude-desktop = prev.claude-desktop.overrideAttrs (old: {
    postInstall = (old.postInstall or "") + "\n" + helpers.mkAsarPatch {
      label = "10 wayland primary monitor (screenshot + click origin)";
      body = ''
        # (1) Inject __cuGetPrimaryOrigin() right before _getMonitors. Queries
        # Mutter DisplayConfig (no unsafe_mode), parses the PRIMARY logical
        # monitor's origin from the GVariant text (the `..., true, [` tuple; the
        # transform field may or may not carry a `uint32 ` prefix, hence the
        # optional group), caches it, and falls back to {0,0} on any error.
        substituteInPlace "$work/contents/.vite/build/index.js" \
          --replace-warn \
            'function _getMonitors(){' \
            'var __cuPrimaryOriginCache=null;function __cuGetPrimaryOrigin(){if(__cuPrimaryOriginCache!==null)return __cuPrimaryOriginCache;var o={x:0,y:0};try{var out=_cp.execSync("gdbus call --session --dest org.gnome.Mutter.DisplayConfig --object-path /org/gnome/Mutter/DisplayConfig --method org.gnome.Mutter.DisplayConfig.GetCurrentState",{encoding:"utf-8",timeout:5000});var m=out.match(/\(([-]?\d+), ([-]?\d+), [\d.]+, (?:uint32 )?\d+, true, \[/);if(m){o={x:parseInt(m[1],10)||0,y:parseInt(m[2],10)||0}}}catch(e){console.warn("[claude-cu] Mutter primary-origin lookup failed, using {0,0}: "+e.message)}__cuPrimaryOriginCache=o;return o;}function _getMonitors(){'

        # (2) _getMonitors: derive primaryId from the Mutter-primary origin
        # instead of trusting Electron's (wrong-on-Wayland) isPrimary. Electron's
        # per-display bounds are correct, so we match by origin.
        substituteInPlace "$work/contents/.vite/build/index.js" \
          --replace-warn \
            'var primaryId=primary?primary.id:displays[0].id;' \
            'var primaryId=primary?primary.id:displays[0].id;try{var _po=__cuGetPrimaryOrigin();var _pm=displays.find(function(dd){return dd.bounds.x===_po.x&&dd.bounds.y===_po.y});if(_pm)primaryId=_pm.id;}catch(e){}'

        # (3a) _moveMouse: single pure absolute move, minus the Mutter-primary
        # origin (undoes ydotool's monitor-local re-add). Replaces the flaky
        # abs(0,0)+sleep+relative idiom.
        substituteInPlace "$work/contents/.vite/build/index.js" \
          --replace-warn \
            '_exec("ydotool mousemove --absolute 0 0");_cp.execSync("sleep 0.05");_exec("ydotool mousemove "+Math.round(x)+" "+Math.round(y));return' \
            'var _po=__cuGetPrimaryOrigin();_exec("ydotool mousemove --absolute "+(Math.round(x)-_po.x)+" "+(Math.round(y)-_po.y));return'

        # (3b) drag: same fix for the drag end-point move.
        substituteInPlace "$work/contents/.vite/build/index.js" \
          --replace-warn \
            '_exec("ydotool mousemove --absolute 0 0");_cp.execSync("sleep 0.05");_exec("ydotool mousemove "+Math.round(end.x)+" "+Math.round(end.y))' \
            'var _po=__cuGetPrimaryOrigin();_exec("ydotool mousemove --absolute "+(Math.round(end.x)-_po.x)+" "+(Math.round(end.y)-_po.y))'
      '';
    };
  });
}
