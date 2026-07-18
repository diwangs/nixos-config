# Unlock the thinking/effort toggle on the Chat surface. model-id-normalization
# + thinking-flag enable it for Cowork/Code; Chat has an extra renderer guard.
#
# The Chat renderer is a code-split app served over the app:// protocol from the
# LOOSE bundle at resources/ion-dist/assets/v1/ (NOT inside app.asar, and NOT at
# patrickjaja's resources/locales/ion-dist path). The gate lives in the entry
# chunk index-*.js:
#
#   $e=le("yukon_silver_thinking"),
#   We=Le.considerEnabledForNonUI&&(F||S&&!Te||te||se)&&!ae,   // effort surface (Chat: false)
#   Ge=$e&&We                                                   // thinking (flag && effort)
#
# consumed downstream as effortSurface:We?"cowork":void 0, thinkingSurface:Ge?...
# Forcing We=!0 makes Chat behave like Cowork; Ge=$e&&!0=$e keeps the thinking
# toggle gated by the (already-enabled) yukon_silver_thinking flag. This is the
# direct descendant of patrickjaja's old `De=!0` fix. CDP-validated live on build
# 1.17377.1: before, Chat's model menu had 0 effort items; after serving the
# patched chunk, Chat shows the Effort submenu (Low/Medium/High) + Thinking
# toggle, identical to Cowork.
#
# FRAGILITY: the anchor is heavy on minified locals (We/Ge/Le/$e re-roll every
# build) and the filename hash varies (hence the glob). Unlike the asar patches,
# a glob that matches nothing — or a drifted anchor — is a SILENT no-op (the loop
# body just doesn't run; --replace-warn only warns when a matched file lacks the
# string). So after any update.sh bump, RUNTIME-VERIFY the Chat surface.
#
# Uses mkLoosePatch (no asar extract/repack), so — unlike the other patches — it
# does not add `asar` to nativeBuildInputs.
#
# Standalone overlay: import after ../overlay.nix; order vs other patches is
# irrelevant (this touches a loose file, the others touch app.asar).
final: prev:
let
  helpers = import ../lib.nix { inherit (final) lib; };
in
{
  claude-desktop = prev.claude-desktop.overrideAttrs (old: {
    postInstall =
      (old.postInstall or "")
      + "\n"
      + helpers.mkLoosePatch {
        label = "chat effort/thinking toggle (ion-dist, loose file)";
        body = ''
          for ionBundle in "$asarRoot/ion-dist/assets/v1/"index-*.js; do
            substituteInPlace "$ionBundle" \
              --replace-warn \
                'We=Le.considerEnabledForNonUI&&(F||S&&!Te||te||se)&&!ae,Ge=$e&&We' \
                'We=!0,Ge=$e&&We'
          done
        '';
      };
  });
}
