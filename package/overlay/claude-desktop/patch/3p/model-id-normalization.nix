# Widen the model-ID normalization regex. Claude Desktop can handle
# non-Anthropic-1p model IDs, but only the dot-based syntax used by Bedrock and
# Vertex, not the slash-based syntax used by OpenRouter. Widening the regex makes
# Claude Desktop recognize the OpenRouter model ID and assign the correct
# capabilities and description (effort slider, fable disablement, 1m context
# across Chat/Cowork/Code). This is the core 3p fix — without it the effort
# slider is absent on Cowork/Code.
#
# Both anchors verified present exactly once in the official build (1.17377.1).
#
# Standalone overlay: import after ../overlay.nix; order vs other patches is
# irrelevant (per-fragment extract/repack — see ../lib.nix).
final: prev:
let
  helpers = import ../lib.nix { inherit (final) lib; };
in
{
  claude-desktop = prev.claude-desktop.overrideAttrs (old: {
    nativeBuildInputs = (old.nativeBuildInputs or [ ]) ++ [ final.asar ];
    postInstall = (old.postInstall or "") + "\n" + helpers.mkAsarPatch {
      label = "model-id normalization";
      body = ''
        substituteInPlace "$work/contents/.vite/build/index.js" \
          --replace-warn \
            '.replace(/^(?:[a-z][a-z0-9-]*\.)?anthropic\./,"")' \
            '.replace(/^(?:[a-z][a-z0-9-]*[./])?anthropic[./]/,"")' \
          --replace-warn \
            '.replace(/-\d{8}$/,"")}' \
            '.replace(/-\d{8}$/,"").replace(/(\d)\.(\d)/g,"$1-$2")}'
      '';
    };
  });
}
