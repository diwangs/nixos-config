# =====================
# oo7 × Chromium Secret-portal token panic fix (patches ashpd)
# =====================
#
# BUG: Chromium (and any Electron app, e.g. Claude Desktop) hangs on startup —
# persistent-cookie / profile init blocks indefinitely — once oo7-portal owns
# `org.freedesktop.impl.portal.Secret` (see aspect/secret.nix). No error is
# printed; the app just never finishes loading its encryption key.
#
# The previous workaround disabled Chromium's portal client entirely
# (`--disable-features=DbusSecretPortal`, see
# package/overlay/claude-desktop/patch/oo7.nix), forcing it onto the Secret
# Service. This fixes the portal itself instead, so ANY portal client works.
#
# ROOT CAUSE (in ashpd, NOT oo7's own code): oo7-portal is a thin backend over
# `ashpd::backend::secret`. ashpd's `HandleToken` is documented as a D-Bus
# *object-path element* ("A valid object path element must only contain the
# ASCII characters [A-Z][a-z][0-9]_") but is actually backed by
# `zbus::names::OwnedMemberName`:
#
#   src/desktop/handle_token.rs:
#       pub struct HandleToken(OwnedMemberName);
#       ...
#       Ok(Self(OwnedMemberName::try_from(value).unwrap()))   // FromStr
#
# A D-Bus *member name* has a STRICTER rule than an object-path element: it
# "Must not begin with a digit" (zbus_names member_name.rs). Chromium's OSCrypt
# picks a random hex `handle_token`; xdg-desktop-portal makes it the last
# segment of the Request object path and hands that path to the backend, where
# ashpd's generated `org.freedesktop.impl.portal.Secret.RetrieveSecret` handler
# does (src/backend/secret.rs):
#
#       HandleToken::try_from(&handle).unwrap()
#
# When the segment starts with a digit — 10 of the 16 hex leading chars, i.e.
# ~10/16 of connections — `OwnedMemberName::try_from` returns Err, `.unwrap()`
# panics INSIDE the zbus method handler, so no reply is ever sent. The frontend
# xdg-desktop-portal waits forever, and so does Chromium.
#
# FIX: back `HandleToken` with a plain `String` (the object-path-element
# semantics the doc comment already describes) while keeping the existing
# `[A-Za-z0-9_]` char check. This drops only the spurious leading-digit
# rejection. `OwnedMemberName` is referenced ONLY inside handle_token.rs (the
# inner value is otherwise touched just by Display/Debug and the Serialize/Type
# derives, all of which behave identically for String — same `s` signature), so
# the change is fully self-contained and fixes the panic at every backend portal
# `HandleToken::try_from(&handle).unwrap()`, not only Secret.
#
# UPSTREAM: already fixed on ashpd `main` (unreleased — main still self-reports
# 0.13.0, same version as the buggy crates.io tag oo7 0.6.0 pins), the exact
# same way (HandleToken now wraps String, with a `from_str("2token").is_ok()`
# regression test). See bilelmoussaoui/ashpd commits:
#   ba5f40fcfbf468a8323b2c795ef00d5ad4071083  handletoken: handle all valid object paths
#   83965c5e2e793a9f0ea35083519983adb89d2d49  handletoken: change error type to separate out error cases
# So this overlay is a stopgap until ashpd cuts a release and nixpkgs' oo7 pulls
# it in — at which point the --replace-fail below stops matching and the build
# fails loudly, signalling us to delete it.
#
# MECHANICS: the bug is in a VENDORED dependency, not oo7's workspace source, so
# unlike ./json.nix we can't patch the top-level `src`. Instead we edit the
# cargo vendor copy. `oo7-portal` uses `rustPlatform.cargoSetupHook`, which in
# postUnpack copies `cargoDeps` to a writable dir and exports `$cargoDepsCopy`;
# our `postPatch` runs before `cargoSetupPostPatchHook` unsets it, so the copy is
# writable and addressable there. The vendor's `.cargo-checksum.json` carries an
# empty `"files"` map (modern fetchCargoVendor), so cargo does NO per-file hash
# check — a bare substituteInPlace needs no checksum fixup. The `ashpd-*` glob
# tolerates patch bumps; `--replace-fail` makes an upstream code change (e.g. a
# real fix landing) fail the build loudly so we know to drop this overlay.
#
# Standalone overlay, imported in ../../../nixos.nix. Supersedes
# package/overlay/claude-desktop/patch/oo7.nix (disabled there). Remove once the
# upstream fix (above) reaches a released ashpd that nixpkgs' oo7 uses.
final: prev: {
  oo7-portal = prev.oo7-portal.overrideAttrs (old: {
    postPatch = (old.postPatch or "") + ''
      substituteInPlace "$cargoDepsCopy"/source-registry-0/ashpd-*/src/desktop/handle_token.rs \
        --replace-fail \
          'use zbus::{names::OwnedMemberName, zvariant::Type};' \
          'use zbus::zvariant::Type;' \
        --replace-fail \
          'pub struct HandleToken(OwnedMemberName);' \
          'pub struct HandleToken(String);' \
        --replace-fail \
          'Self(OwnedMemberName::try_from(token).unwrap())' \
          'Self(token)' \
        --replace-fail \
          'Ok(Self(OwnedMemberName::try_from(value).unwrap()))' \
          'Ok(Self(value.to_owned()))'
    '';
  });
}
