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

    postInstall =
      (old.postInstall or "")
      + "\n"
      + helpers.mkAsarPatch {
        label = "Claude Code local binary";
        body = ''
          target=${helpers.findChunk ",process.env.CLAUDE_CODE_LOCAL_BINARY}async initLocalBinary"}
          test -n "$target" || { echo "cli-path: initLocalBinary anchor not found in any bundle chunk"; exit 1; }
          substituteInPlace "$target" \
            --replace-fail \
              ',process.env.CLAUDE_CODE_LOCAL_BINARY}async initLocalBinary' \
              ',process.env.CLAUDE_CODE_LOCAL_BINARY&&(this.localBinaryInitPromise=this.initLocalBinary(process.env.CLAUDE_CODE_LOCAL_BINARY))}async initLocalBinary'
        '';
      };
  });
}
