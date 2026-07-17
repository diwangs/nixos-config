# Disable the guard that makes the app exit when the remote debug port is
# enabled. Not directly related to the OpenRouter problem, but a necessary
# intermediate step to enable dynamic analysis (CDP) of the bundle.
#
# The guard is a tertiary statement that checks process.argv and exits; it lives
# in index.pre.js (not index.js). Anchor verified present exactly once in the
# official build (1.17377.1).
#
# Standalone overlay: import after ./overlay.nix in ../../../../nixos.nix;
# order vs other patches is irrelevant (per-fragment extract/repack — see
# ./lib.nix). Each patch adds `asar` to nativeBuildInputs itself so it works no
# matter which subset of patches is imported.
final: prev:
let
  helpers = import ./lib.nix { inherit (final) lib; };
in
{
  claude-desktop = prev.claude-desktop.overrideAttrs (old: {
    nativeBuildInputs = (old.nativeBuildInputs or [ ]) ++ [ final.asar ];
    postInstall = (old.postInstall or "") + "\n" + helpers.mkAsarPatch {
      label = "debug-port guard";
      body = ''
        substituteInPlace "$work/contents/.vite/build/index.pre.js" \
          --replace-warn \
            '&&process.exit(1)' \
            '&&void 0'
      '';
    };
  });
}
