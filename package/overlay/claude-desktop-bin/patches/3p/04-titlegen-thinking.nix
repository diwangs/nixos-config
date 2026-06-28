# Title-gen patch: disable thinking for title generation, because OpenRouter
# reasoning breaks the `claude -p` output (no <title> tag, leaving "Untitled"
# chats). Title-gen has TWO spawn paths, picked by eR() = VM-available:
#   - host mode (mLn): env built by M_A() -> the NODE_USE_SYSTEM_CA block.
#     Used when no cowork-service/VM backend exists.
#   - vm mode (wLn): env built inline, spawned inside the Cowork sandbox.
#     Used once claude-cowork-service is installed.
# Both need MAX_THINKING_TOKENS:"0"; patch each env object. (Before the
# cowork-service was added, only host mode ran, so the second substitution is
# what fixed the regression when VM mode kicked in.)
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
      label = "title-gen thinking disable (MAX_THINKING_TOKENS=0)";
      body = ''
        substituteInPlace "$work/contents/.vite/build/index.js" \
          --replace-warn \
            'NODE_USE_SYSTEM_CA:"1",CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC:"1"}' \
            'NODE_USE_SYSTEM_CA:"1",CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC:"1",MAX_THINKING_TOKENS:"0"}' \
          --replace-warn \
            '.overrides,CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC:"1"}' \
            '.overrides,CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC:"1",MAX_THINKING_TOKENS:"0"}'
      '';
    };
  });
}
