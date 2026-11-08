# Make Claude Desktop's existing CLAUDE_CODE_LOCAL_BINARY override functional.
# The official Linux bundle keeps initLocalBinary() and getLocalBinaryPath(),
# but since 4.x ClaudeCodeManager's constructor no longer reads the variable at
# all (it used to read and discard it), so the override is unreachable. Append
# the read to the end of the constructor, which directly precedes
# initLocalBinary() in the bundle.
#
# The substitution is injected into `passthru.unwrapped` (which owns app.asar)
# so upstream's FHS wrapper picks it up — see ./lib.nix for that plumbing.
#
# Import AFTER ../overlay.nix in ../../../../nixos.nix.
final: prev:
let
  draft = import ./lib.nix { inherit final prev; };
in
draft.mkPatch {
  postFixup = draft.mkAsarPatch {
    label = "Claude Code local binary";
    body = ''
      target=${draft.findChunk "}async initLocalBinary("}
      test -n "$target" || { echo "cli-path: initLocalBinary anchor not found in any bundle chunk"; exit 1; }
      substituteInPlace "$target" \
        --replace-fail \
          '}async initLocalBinary(' \
          ';process.env.CLAUDE_CODE_LOCAL_BINARY&&(this.localBinaryInitPromise=this.initLocalBinary(process.env.CLAUDE_CODE_LOCAL_BINARY))}async initLocalBinary('
    '';
  };
}
