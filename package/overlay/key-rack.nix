# =====================
# key-rack version bump (0.4.0 -> 0.6.0)
# =====================
#
# nixpkgs pins key-rack to 0.4.0. Upstream (gitlab.gnome.org/World/key-rack,
# formerly sophie-h/key-rack) has no 0.6.0 *tag* yet -- Cargo.toml/meson.build
# on `main` were bumped to 0.6.0 by the "Release 0.6.0" commit
# (274afb41a192297176f80cc7e6234a51076b65e5, 2026-07-20) but the tag push
# hasn't landed. Pin to that commit by rev instead of waiting on the tag.
#
# The nixpkgs derivation also carries ./0001-fix-E0716.patch, a workaround for
# a rustc<1.79 borrow-checker error in src/data/item.rs. That code path was
# refactored away by 0.6.0 (no `&format!(..)` returned as `&str` in
# ItemSchema), so the patch no longer applies and is dropped here.
#
# 0.6.0's data/meson.build also turns on gnome.post_install's
# update_desktop_database, which needs `update-desktop-database` on PATH at
# build time (desktop-file-utils); 0.4.0 didn't request it.
#
# key-rack/0001-show-empty-flatpak-portal-entries.patch: local preference
# patch (not an upstream bug fix). Upstream hides a Flatpak app's entry on
# the Overview page entirely when its portal-managed keyring
# (~/.var/app/<app-id>/data/keyrings/default.keyring) has zero items --
# see overview_page.rs's `not_empty_filter`. Some apps (e.g. Slack) register
# a Secret-portal wrapping key but never populate that keyring file, so they
# never show up at all. Dropping `not_empty_filter` from both EveryFilters
# surfaces those apps too, as empty entries, so it's visible which
# installed apps are using the Secret portal in the first place.
#
# Standalone overlay: import in ../../nixos.nix. Replace with a plain
# nixpkgs version bump once upstream tags 0.6.0 and it reaches nixpkgs
# (the empty-entries patch should be kept regardless, it's a preference,
# not a version-specific fix).
final: prev:
let
  version = "0.6.0";
  src = final.fetchFromGitLab {
    domain = "gitlab.gnome.org";
    owner = "World";
    repo = "key-rack";
    rev = "274afb41a192297176f80cc7e6234a51076b65e5";
    hash = "sha256-7XkZ0/B70hKJaENGhm0P/GowTnbPTTz/HVw9WzFZy7I=";
  };
in
{
  key-rack = prev.key-rack.overrideAttrs (old: {
    inherit version src;

    patches = [ ./key-rack/0001-show-empty-flatpak-portal-entries.patch ];

    nativeBuildInputs = (old.nativeBuildInputs or [ ]) ++ [
      final.desktop-file-utils
    ];

    cargoDeps = final.rustPlatform.fetchCargoVendor {
      inherit (old) pname;
      inherit version src;
      hash = "sha256-UGlnQUX0vl00y9la1QF0jx7xdZA3/mK1QyDzSRs8Jrs=";
    };
  });
}
