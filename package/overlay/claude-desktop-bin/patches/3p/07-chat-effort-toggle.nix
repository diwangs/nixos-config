# Fourth patch: unlock the thinking/effort toggle on the Chat surface (the
# third patch enables it for Cowork/Code; Chat has an extra renderer guard). The
# guard `De` is false on Chat (considerEnabledForNonUI = the Cowork capability
# store), so force it true. CDP-confirmed: with this, Chat's model selector
# shows Effort/thinking like Code/Cowork.
#
# Unlike the other patches, the ion bundle is a LOOSE file in the output
# (patrickjaja ships it at resources/locales/ion-dist, not inside app.asar), so
# this uses mkLoosePatch — no extract/repack. Its filename hash varies per
# build, hence the glob. NOTE: a missing glob match is a silent no-op (the loop
# body never runs) — not even a warning — so confirm the path still exists if
# Chat loses the toggle.
#
# TODO: this is the least robust patch (many minified variables). It warns
# rather than fails on a miss, so a build won't break — but check the Chat
# surface at runtime, since a drifted anchor no-ops silently.
#
# Standalone overlay: import after ./base.nix; order vs other patches is
# irrelevant (per-fragment extract/repack — see ../base.nix).
final: prev:
let
  helpers = import ../../lib.nix { inherit (final) lib; };
in
{
  claude-desktop = prev.claude-desktop.overrideAttrs (old: {
    postInstall = (old.postInstall or "") + "\n" + helpers.mkLoosePatch {
      label = "07 chat effort/thinking toggle (ion-dist, loose file)";
      body = ''
        for ionBundle in "$asarRoot/locales/ion-dist/assets/v1/"index-*.js; do
          substituteInPlace "$ionBundle" \
            --replace-warn \
              'De=xe.considerEnabledForNonUI&&(_&&!ve||Q||j&&G)&&!Y,Pe=Ae&&De&&!J' \
              'De=!0,Pe=Ae&&De&&!J'
        done
      '';
    };
  });
}
