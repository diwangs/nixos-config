/*

Problems when using GNOME's Portal Screecast:
- Computer Use does not read the selected monitor's position and size 
  returned by Portal and always uses the primary monitor's (per Electron).
  However, Mutter and Electron might disagree on which monitor is primary. 
- Computer Use assumes screencast is delivered in desktop-absolute dimension
  and does its own cropping to select the primary monitor. However, Portal 
  already selects the screen for its client and delivered in the selected's 
  monitor dimension.

In our setup, these two problems sometimes manfiest themselves in screencast 
that is cropped just in the left half of the selected landscape screen. This 
is caused by Electron choosing the potrait monitor as the primary, then 
cropping the arrived image to its dimension.

To fix these two problems at once, we need to read the selected monitor data
returned by Portal and adjust the cropping according to it.

Problem -> screenshot is done after position is guessed.

NOTE: the Mutter and Electron primary monitor mismatch still lingers, but it's 
benign if the fix is applied.

*/


# Old:
# Tenth patch: fix Computer Use SCREENSHOT (wrong monitor/region) on
# native-Wayland GNOME with a multi-monitor, mixed-orientation layout. Runs the
# app under native Wayland (--ozone-platform=wayland) with ydotool for input and
# portal+PipeWire for capture. Supersedes the XWayland workarounds (old patches
# 06+09, deleted) and folds the portal-crop fix (old patch 09) back in, in a
# robust form. (The ydotool CLICK/DRAG input fixes live in the separate
# ./11-ydotool-multimonitor.nix patch.)
#
# === 1. LAYOUT + ROOT CAUSE (Mutter vs Electron disagree on the primary) ===
#
# This box's layout (Mutter GetCurrentState is ground truth):
#   DP-7 landscape 2560x1440 at logical origin (1080,480)  <- Mutter PRIMARY
#   DP-8 portrait  1080x1920 at logical origin (0,0)
#   desktop bbox 3640x1920, bottoms aligned.
#
# CU reasons in DESKTOP-ABSOLUTE coordinates keyed off the Mutter-primary origin
# (1080,480): the executor maps model clicks with `__txC(c) = c*__cuScale +
# __cuActiveOrigin`, and __cuActiveOrigin is the chosen monitor's desktop origin.
# The root cause of every bug below is that the two subsystems CU leans on do not
# agree with Mutter on that frame:
#   - ELECTRON mis-reports the primary under native Wayland: getPrimaryDisplay()
#     returns the portrait DP-8 (1080x1920 @ 0,0) and getCursorScreenPoint()
#     always returns (0,0). Its per-display BOUNDS are correct, though — only the
#     isPrimary flag (and the cursor) is wrong.
#   - The PORTAL stream and YDOTOOL both work in MONITOR-LOCAL coordinates of the
#     primary monitor, not the desktop-absolute frame CU feeds them.
# So the fix everywhere is to establish the Mutter-primary origin authoritatively
# and translate to/from it. Edit (0), shared by all: inject
# `__cuGetPrimaryOrigin()` — queries Mutter DisplayConfig GetCurrentState (a
# STANDARD unprivileged read, same API as gnome-control-center's Displays panel;
# NO unsafe_mode; `gdbus` is already on the app PATH via base.nix portal deps),
# parses the primary logical-monitor origin, caches it, falls back to {0,0} on
# error. (Oracle for all live verification below: `global.get_pointer()` via
# GNOME Shell Eval, which DOES need unsafe_mode — but only for testing, not at
# runtime.) All edits target the JS executor `globalThis.__linuxExecutor` (the
# active Linux/GNOME CU path; @ant/claude-native ships EMPTY on Linux and the
# kwin-portal-bridge path is KDE-only) plus the embedded portal python; they
# compose with patch 08 (downsample/__cuScale) and 05 (CU enable), disjoint
# anchors.
#
# === 2. PORTAL SCREENCAST (Electron picks wrong monitor; crop uses wrong frame) ===
#
#   (2a) WRONG MONITOR / aspect. The screenshot handler picks the default display
#        from `isPrimary`, which `_getMonitors` copies from Electron's broken
#        getPrimaryDisplay() → it captures the portrait DP-8 and sets
#        __cuActiveOrigin={0,0}.
#        FIX: `_getMonitors` sets `primaryId` to the Electron display whose
#        BOUNDS ORIGIN matches the Mutter primary (bounds are correct; only the
#        flag is wrong). Now the default capture + __cuActiveOrigin lock to DP-7.
#        Verified: listDisplays reports DP-7 (2560x1440 @ 1080,480) isPrimary.
#
#   (2b) WRONG CROP — captures only the bottom-right band of the primary. The
#        PipeWire ScreenCast stream for one selected monitor arrives in
#        MONITOR-LOCAL pixels (top-left 0,0), but the executor crops it with the
#        monitor's DESKTOP-ABSOLUTE rect (1080,480,w,h). Cropping a monitor-local
#        2560x1440 buffer at (1080,480) clamps to 1480x960 = (2560-1080)x
#        (1440-480) (confirmed live: screenshot() returned 1332x864 @
#        __cuScale=1.111, i.e. 1480x960 pre-downsample).
#        FIX: the portal Start response already reports the stream's desktop
#        `position` (measured: position:(1080,480), size:(2560,1440)) but the
#        code DISCARDS it (keeps sl[0][0] node-id, drops sl[0][1] props). Capture
#        it, then crop at `requested_origin - streamPosition` (floored at 0).
#        Verified against the live restore-token: full crop -> 2560x1440,
#        sub-region (1180,580,300,200) -> correct 300x200. Replaces old patch 09
#        ROBUSTLY: a fixed (0,0) was only right for a monitor-local node and a
#        fixed (x,y) only for a full-desktop node; subtracting the reported
#        position is correct for BOTH. (This is also why disabling patch 09 only
#        "worked before" by accident — the buffer is monitor-local every boot;
#        the apparent reboot non-determinism was a BUILD REGRESSION: exactly one
#        prior store build (gen 780) had the old (0,0) crop compiled in, the
#        deletion shipped in gen 782, and the reboot just activated gen 782 for
#        the first time. Not environmental.) Untouched: the grim/scrot/
#        gnome-screenshot branches (they get whole-desktop buffers and still need
#        the absolute origin).
#
# (CLICK/DRAG input — the ydotool multi-monitor coordinate fixes — moved to the
# separate ./11-ydotool-multimonitor.nix patch.)
#
# Standalone overlay: import after ./base.nix; order vs other patches is
# irrelevant (per-fragment extract/repack — see ../base.nix). The python edits
# use bash double-quoted substituteInPlace args (the python literals contain
# single quotes); the JS edits keep single-quoted args (JS uses double quotes).
final: prev:
let
  helpers = import ../../lib.nix { inherit (final) lib; };
in
{
  claude-desktop = prev.claude-desktop.overrideAttrs (old: {
    postInstall = (old.postInstall or "") + "\n" + helpers.mkAsarPatch {
      label = "10 wayland primary monitor (screenshot monitor + crop)";
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

        # (3a) Portal screenshot: capture the stream's desktop position from the
        # Start response (sl[0][1] props dict, currently dropped). Appended to the
        # node-id assignment as a second statement under the same `if sl:`.
        # bash double-quotes: the python literals contain single quotes.
        substituteInPlace "$work/contents/.vite/build/index.js" \
          --replace-warn \
            "if sl: state['node_id']=sl[0][0] if isinstance(sl[0],tuple) else sl[0]" \
            "if sl: state['node_id']=sl[0][0] if isinstance(sl[0],tuple) else sl[0];state['pos']=(sl[0][1].get('position') if (isinstance(sl[0],tuple) and len(sl[0])>1 and hasattr(sl[0][1],'get')) else None)"

        # (3b) Portal screenshot: convert the desktop-absolute crop origin to
        # monitor-local by subtracting the captured stream position (floored at
        # 0). `or (0,0)` degrades to the prior behavior if no position was
        # reported. Single python line (semicolons) — no new newlines/indent.
        substituteInPlace "$work/contents/.vite/build/index.js" \
          --replace-warn \
            "cx=min(cx,pw-1);cy=min(cy,ph-1);cw=min(cw,pw-cx);ch=min(ch,ph-cy)" \
            "_pp=state.get('pos') or (0,0);cx=max(0,cx-int(_pp[0]));cy=max(0,cy-int(_pp[1]));cx=min(cx,pw-1);cy=min(cy,ph-1);cw=min(cw,pw-cx);ch=min(ch,ph-cy)"
      '';
    };
  });
}
