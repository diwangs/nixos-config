/*

While Anthropic model themselves issue click coordinate within a monitor, 
`ydotool` is set up to act with a desktop-bbox coordinate (transformed by 
executor based on `__cuActiveOrigin`). However, `ydotool` is a rel-only device 
and has quirks with multi-monitor setup:
https://github.com/ReimuNotMoe/ydotool/issues/273#issuecomment-3631264290

- Absolute movement is anchored (where 0,0 is) to the top-left monitor the
  cursor is *currently* in.
- Absolute movement that exceeds the size of said monitor will succeed if
  the coordinate is positive (i.e., there is another monitor below or on
  the right of the current monitor). This will *move the anchor* to the
  adjacent monitor.
- Absolute movement with negative coordinate will get floored and only move
  to the current monitor's up and/or left edge.
- You could use relative movement to move to a monitor above or on the left
  of the current one, but if the final position is invalid (outside of
  bbox), then you would similarly only move to the current monitor's up
  and/or left edge.

To account for these quirks, the play is to do repeated *relative* negative
movements to any point within the upper-left-most monitor (where monitor 
origin === the bbox origin), then issue an *absolute* coordinate relative 
to the bbox origin. The negative movement must be quantized so that it will 
never be invalid regardless of source.

In our case, that's `3 x (-1080,0)`.

*/

final: prev:
let
  helpers = import ../../lib.nix { inherit (final) lib; };
in
{
  claude-desktop = prev.claude-desktop.overrideAttrs (old: {
    postInstall = (old.postInstall or "") + "\n" + helpers.mkAsarPatch {
      label = "11 ydotool multi-monitor (walk to bbox origin, then absolute)";
      body = ''
        substituteInPlace "$work/contents/.vite/build/index.js" \
          --replace-warn \
            '_exec("ydotool mousemove --absolute 0 0");_cp.execSync("sleep 0.05");_exec("ydotool mousemove "+Math.round(x)+" "+Math.round(y));return' \
            'Array.from({length:3}).forEach(()=>_exec("ydotool mousemove -- -1080 0"));_exec("ydotool mousemove --absolute "+Math.round(x)+" "+Math.round(y));return'

        substituteInPlace "$work/contents/.vite/build/index.js" \
          --replace-warn \
            '_exec("ydotool mousemove --absolute 0 0");_cp.execSync("sleep 0.05");_exec("ydotool mousemove "+Math.round(end.x)+" "+Math.round(end.y))' \
            'if(start){_exec("ydotool mousemove -- "+(Math.round(end.x)-Math.round(start.x))+" "+(Math.round(end.y)-Math.round(start.y)))}else{Array.from({length:3}).forEach(()=>_exec("ydotool mousemove -- -1080 0"));_exec("ydotool mousemove --absolute "+Math.round(end.x)+" "+Math.round(end.y))}'
      '';
    };
  });
}
