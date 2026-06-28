# Fifth patch: enable Computer Use ("chicago") in 3p mode. Upstream's
# fix_computer_use_linux.nim already forces the platform/registration/preference
# gates true on Linux, but the local-agent session manager still computes the
# per-session tool offering as cuCanUseToolEnabled = …&&it("<cuCanUseTool>") and
# the master chicago_config = cn("<chicagoConfig>","enabled",false). Those read
# raw GrowthBook flags that 3p/OpenRouter never delivers, so they resolve false
# (CDP-confirmed: the [chicago] startup log printed `enabled=false`), and the
# model is never offered the computer-use tools. Same failure class as the
# yukon_silver_thinking toggle: seed both flags into the same 3p bootstrap map
# the third patch extends. cn() returns the caller's default for any absent
# sub-key, so {enabled:!0} is enough — the other chicago sub-gates fall back to
# upstream's defaults. Anchor on 574905726:sc(!0), (a stable element of that
# map, distinct from the third patch's return{574905726: anchor, so the two
# don't collide).
#
# The flag IDs are SERVER-assigned GrowthBook IDs, NOT mul31(name) hashes
# (verified: mul31 "chicago_config" = 2365328567 ≠ 1291166712, and no preimage
# exists in the bundle). They're transcribed verbatim from the source repo's
# baseline/CLAUDE_FEATURE_FLAGS.md, whose version-history table is authoritative
# if a future build renames them.
#
# Standalone overlay: import after ./base.nix; order vs other patches is
# irrelevant (per-fragment extract/repack — see ../base.nix).
final: prev:
let
  helpers = import ../../lib.nix { inherit (final) lib; };
  cuCanUseToolFlag = "2486083521";  # "CU can-use-tool" — the 3p-only gate
  chicagoConfigFlag = "1291166712"; # "chicago_config" master enable (.enabled)
in
{
  claude-desktop = prev.claude-desktop.overrideAttrs (old: {
    postInstall = (old.postInstall or "") + "\n" + helpers.mkAsarPatch {
      label = "05 computer-use flags (chicago)";
      body = ''
        substituteInPlace "$work/contents/.vite/build/index.js" \
          --replace-warn \
            '574905726:sc(!0),' \
            '574905726:sc(!0),"${cuCanUseToolFlag}":{defaultValue:!0},"${chicagoConfigFlag}":{defaultValue:{enabled:!0}},'
      '';
    };
  });
}
