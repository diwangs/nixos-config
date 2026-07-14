# Make Claude Desktop's existing CLAUDE_CODE_LOCAL_BINARY override functional.
# The official Linux bundle reads the variable in ClaudeCodeManager's
# constructor but discards it, leaving initLocalBinary() unreachable.
final: prev:
let
  helpers = import ./lib.nix { inherit (final) lib; };
in
{
  claude-desktop = prev.claude-desktop.overrideAttrs (old: {
    nativeBuildInputs = (old.nativeBuildInputs or [ ]) ++ [ final.asar ];

    postInstall = (old.postInstall or "") + "\n" + helpers.mkAsarPatch {
      label = "Claude Code local binary";
      body = ''
        substituteInPlace "$work/contents/.vite/build/index.js" \
          --replace-fail \
            ',process.env.CLAUDE_CODE_LOCAL_BINARY}async initLocalBinary' \
            ',process.env.CLAUDE_CODE_LOCAL_BINARY&&(this.localBinaryInitPromise=this.initLocalBinary(process.env.CLAUDE_CODE_LOCAL_BINARY))}async initLocalBinary'
      '';
    };
  });
}
