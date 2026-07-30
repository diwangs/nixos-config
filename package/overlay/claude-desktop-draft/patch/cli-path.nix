# Make Claude Desktop's existing CLAUDE_CODE_LOCAL_BINARY override functional.
# The official Linux bundle reads the variable in ClaudeCodeManager's
# constructor but discards it, leaving initLocalBinary() unreachable.
#
# Draft-packaging port of ../../claude-desktop/patch/cli-path.nix: same
# substitution, but applied to `passthru.unwrapped` (which owns app.asar) with
# the FHS wrapper rebuilt around it — see ./lib.nix for that plumbing.
#
# Import AFTER ../overlay.nix in ../../../../nixos.nix.
final: prev:
let
  helpers = import ../../claude-desktop/patch/lib.nix { inherit (final) lib; };
  draft = import ./lib.nix { inherit final prev; };
in
draft.mkPatch {
  postFixup = helpers.mkAsarPatch {
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
}
