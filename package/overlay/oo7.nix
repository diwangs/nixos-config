# =====================
# oo7 → git main (fixes both the content-type reject and the portal-token panic)
# =====================
#
# This single overlay supersedes the two hand-patch overlays that used to live
# in ./oo7/ (json.nix + portal-token.nix). Both bugs are now fixed upstream and
# building oo7 from `main` carries both fixes, so we point the package at a
# pinned main commit instead of maintaining substituteInPlace patches.
#
# BUG 1 — content type (was ./oo7/json.nix): oo7's Secret Service daemon
# rejected spec-legal MIME content types, so `aws-vault add` (which labels its
# secret "application/json") failed with `Invalid content type: application/json`.
# Fixed upstream in linux-credentials/oo7#537: client/src/secret.rs now maps
# text/plain, text/utf8 AND application/json to ContentType::Text.
#
# BUG 2 — portal token panic (was ./oo7/portal-token.nix): oo7-portal is a thin
# backend over ashpd, whose HandleToken wrapped a D-Bus `OwnedMemberName` and
# panicked on a digit-leading token (Chromium/Electron OSCrypt picks a random
# hex token; ~10/16 lead with a digit), hanging Claude Desktop on startup. Fixed
# in ashpd (HandleToken now wraps a plain String, with a `from_str("2token")`
# regression test) and released as ashpd 0.13.13 — which oo7 main's Cargo.lock
# now pins (up from the buggy 0.13.0). So no ashpd source patch is needed here;
# the newer pin pulls the fix in via the normal vendor path.
#
# MECHANICS: nixpkgs' oo7-server and oo7-portal both take `oo7` as an input and
# `inherit (oo7) version src cargoDeps`, resolved from the package set fixpoint —
# so overriding `oo7`'s src + cargoDeps here propagates to both daemon and portal
# automatically; we don't touch oo7-server/oo7-portal directly. The Cargo.lock
# changed vs 0.6.0 (ashpd 0.13.0 → 0.13.13, etc.), so cargoDeps is regenerated
# with a fresh hash. meta.changelog is repointed at the pinned commit because the
# stock definition interpolates `finalAttrs.src.tag`, which a rev-pinned src lacks.
#
# Pinned to linux-credentials/oo7 main @ ee9c75b (2026-07-24). Revisit / drop
# once nixpkgs ships an oo7 release (> 0.6.0) that carries both fixes.
final: prev:
let
  rev = "ee9c75b7be27ae469d93cc254037b19de6897428";
  version = "0.6.0-unstable-2026-07-24";
  src = prev.fetchFromGitHub {
    owner = "linux-credentials";
    repo = "oo7";
    inherit rev;
    hash = "sha256-Qjt9xlcbWBPgWJeUhEefDkZpvNtPQ1gVolVV8dCb1f0=";
  };
in
{
  oo7 = prev.oo7.overrideAttrs (old: {
    inherit version src;
    cargoDeps = prev.rustPlatform.fetchCargoVendor {
      inherit src;
      name = "${old.pname}-${version}";
      hash = "sha256-t6+YSABITczJg83ZbUyApx6y8x/FKfLoKntiRhNMxGM=";
    };
    meta = old.meta // {
      changelog = "https://github.com/linux-credentials/oo7/commits/${rev}";
    };
  });
}
