# Enable the `yukon_silver_thinking` feature flag. model-id-normalization enables
# fable disablement and the effort slider in Cowork/Code, but not the thinking
# toggle. Setting this flag in the 3p bootstrap seed map enables it in Cowork.
# The seed map keys flags by their `mul31` hash, which we compute from the flag
# NAME via the mul31 helper (yukon_silver_thinking -> 1658632017) rather than
# hardcoding the number. P.S. `yukonSilver` ~ Cowork's VM.
#
# Anchor `return{${mul31 "yukon_silver"}:` (i.e. return{574905726:) verified
# present exactly once in the official build (1.17377.1).
#
# Standalone overlay: import after ../overlay.nix; order vs other patches is
# irrelevant (per-fragment extract/repack — see ../lib.nix).
final: prev:
let
  helpers = import ../lib.nix { inherit (final) lib; };
  inherit (helpers) mul31;
in
{
  claude-desktop = prev.claude-desktop.overrideAttrs (old: {
    nativeBuildInputs = (old.nativeBuildInputs or [ ]) ++ [ final.asar ];
    postInstall = (old.postInstall or "") + "\n" + helpers.mkAsarPatch {
      label = "thinking-toggle flag (yukon_silver_thinking)";
      body = ''
        substituteInPlace "$work/contents/.vite/build/index.js" \
          --replace-warn \
            'return{${toString (mul31 "yukon_silver")}:' \
            'return{"${toString (mul31 "yukon_silver_thinking")}":{defaultValue:!0},${toString (mul31 "yukon_silver")}:'
      '';
    };
  });
}
