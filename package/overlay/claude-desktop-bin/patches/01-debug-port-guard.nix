# First patch: disable the guard that makes the app exit when the remote debug
# port is enabled. Not directly related to the OpenRouter problem, but a
# necessary intermediate step to enable dynamic analysis (CDP) of the bundle.
#
# The guard is a tertiary statement that checks process.argv and exits; it lives
# in index.pre.js (not index.js).
#
# Standalone overlay: import after ./base.nix; order vs other patches is
# irrelevant (per-fragment extract/repack — see ../base.nix).
final: prev:
let
  helpers = import ../lib.nix { inherit (final) lib; };
in
{
  claude-desktop = prev.claude-desktop.overrideAttrs (old: {
    postInstall = (old.postInstall or "") + "\n" + helpers.mkAsarPatch {
      label = "01 debug-port guard";
      body = ''
        substituteInPlace "$work/contents/.vite/build/index.pre.js" \
          --replace-warn \
            '&&process.exit(1)' \
            '&&void 0'
      '';
    };
  });
}
