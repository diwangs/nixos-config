# Disable thinking for title generation, because OpenRouter reasoning breaks the
# `claude -p` output (no <title> tag, leaving "Untitled" chats). Title-gen has
# TWO spawn paths, picked by VM-availability:
#   - host mode: env built with NODE_USE_SYSTEM_CA:"1",...NONESSENTIAL_TRAFFIC.
#     Used when no VM backend is available.
#   - vm mode: env built with ...resolveCredentialOverrides(...).overrides,
#     ...NONESSENTIAL_TRAFFIC. Spawned inside the Cowork sandbox.
# Both need MAX_THINKING_TOKENS:"0"; patch each env object.
#
# Both anchors verified present exactly once in the official build (1.17377.1).
# The 2 pre-existing MAX_THINKING_TOKENS strings in the bundle are an env-name
# list and a DEFAULT_ constant — NOT these env objects — so the additions are
# non-redundant and land exactly where intended.
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
    postInstall =
      (old.postInstall or "")
      + "\n"
      + helpers.mkAsarPatch {
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
