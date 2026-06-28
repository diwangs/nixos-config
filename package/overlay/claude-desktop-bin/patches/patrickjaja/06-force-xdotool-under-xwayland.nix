# Sixth patch: route Computer Use INPUT through xdotool when running under
# XWayland, instead of ydotool.
#
# Why: on this multi-monitor GNOME/Mutter setup, Electron's NATIVE-Wayland
# display API is broken — getPrimaryDisplay() picks the wrong monitor and
# getCursorScreenPoint() always returns (0,0) — so Computer Use clicks land on
# the wrong screen. Running the app under XWayland (CLAUDE_USE_XWAYLAND=1, set
# in package/home-manager.nix) fixes Electron's display/cursor reporting AND the
# screenshot cascade; measured under XWayland, `xdotool mousemove --sync` and
# `xdotool getmouselocation` are pixel-perfect and agree with GNOME ground truth
# (global.get_pointer()).
#
# BUT the executor still routes INPUT via ydotool, because its `_isWayland()`
# keys off XDG_SESSION_TYPE (still "wayland" on a Wayland session regardless of
# Electron's render backend). And ydotool's `mousemove --absolute` is
# non-deterministic on multi-output Mutter (first move lands at arg, repeats at
# arg+origin), so no coordinate math fixes that path.
#
# Fix: short-circuit `_checkYdotool()` to false when the app is running under
# XWayland (detected by `--ozone-platform=x11` in process.argv, which the
# launcher adds for CLAUDE_USE_XWAYLAND=1). Every INPUT action (move, click,
# type, key, drag, scroll) gates on `_wayland && _checkYdotool()`, so this
# routes them all to the verified xdotool branch. Screenshots gate on `_wayland`
# alone (NOT _checkYdotool), so they are deliberately left on the working
# native/portal path — this patch does not touch them. The false return is a
# first-class fallback in the executor (the "ydotoold not running" path), not a
# hack, and `_ydotoolOk` caching still works since we set it before returning.
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
      label = "06 force xdotool input under XWayland";
      body = ''
        # (a) Route input to xdotool under XWayland (see header).
        substituteInPlace "$work/contents/.vite/build/index.js" \
          --replace-warn \
            'function _checkYdotool(){if(_ydotoolOk!==null)return _ydotoolOk;' \
            'function _checkYdotool(){if(_ydotoolOk!==null)return _ydotoolOk;if(process.argv.some(function(a){return a==="--ozone-platform=x11"})){_ydotoolOk=false;return false}'

        # (b) Drop `--sync` from the xdotool pointer moves. Under XWayland,
        # `xdotool mousemove --sync` blocks forever waiting for a pointer-position
        # confirmation event the X server never delivers, so the executor's
        # execSync times out (`spawnSync /bin/sh ETIMEDOUT`) and no click happens.
        # Plain `mousemove` (no --sync) returns in ~8ms and is still pixel-perfect
        # (measured: target == landed on every coord). Both move sites — the
        # pointer move and the drag end-point — share this exact substring, so one
        # substitution (replace-all is the default) fixes both.
        substituteInPlace "$work/contents/.vite/build/index.js" \
          --replace-warn \
            'xdotool mousemove --sync ' \
            'xdotool mousemove '
      '';
    };
  });
}
