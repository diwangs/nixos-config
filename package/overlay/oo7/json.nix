# =====================
# oo7 × free-form Secret Service content-type fix
# =====================
#
# BUG: `aws-vault add` fails with
#   aws-vault: error: add: Invalid content type: application/json
# once oo7-daemon owns org.freedesktop.secrets (see aspect/secret.nix). The
# error is NOT from aws-vault; it is a D-Bus error returned by the daemon.
#
# ROOT CAUSE: the org.freedesktop.Secret Service spec documents an item's
# `content_type` as a free-form MIME string. oo7, however, collapses it into a
# two-variant enum and REJECTS anything outside a hardcoded whitelist:
#
#   client/src/secret.rs — ContentType::from_str:
#       "text/plain"               => Ok(Self::Text),
#       "application/octet-stream" => Ok(Self::Blob),
#       e => Err(format!("Invalid content type: {e}")),
#
# The daemon deserializes each incoming secret's content_type through this
# `FromStr` (via ContentType's Deserialize impl, on field 3 of the
# `(oayays)` DBusSecretInner tuple in client/src/dbus/api/secret.rs), so any
# client that labels its secret with a legal-but-unlisted MIME type — e.g.
# byteness/keyring, aws-vault's backend, which hardcodes "application/json" —
# gets its whole SetSecret/CreateItem rejected. gnome-keyring stored the string
# verbatim, so this worked before the migration.
#
# FIX: map every unrecognized content type to `Blob` instead of erroring.
# ContentType only distinguishes UTF-8 `Text` from opaque `Blob` bytes; a
# secret whose declared type we don't specifically model is safely treated as
# opaque bytes and round-trips losslessly (`Secret::with_content_type` +
# `as_bytes`). This stops the daemon rejecting spec-legal content types while
# preserving the existing text/octet-stream behavior. This is the change worth
# reporting upstream to linux-credentials/oo7; the previous local workaround
# relabeled the write inside aws-vault (see git history: package/overlay/
# aws-vault.nix) rather than fixing the over-strict whitelist here.
#
# MECHANICS: the runtime daemon is `oo7-server` (the `oo7` attribute is only
# the CLI). It is a meson/stdenv build that inherits `oo7`'s `src`/`cargoDeps`
# and sets `sourceRoot = ".../server"`, so the shared client crate lives at
# `../client` relative to the build dir. Patching a workspace source file does
# not touch Cargo.lock, so cargoDeps/cargoHash are unaffected.
#
# Standalone overlay, meant to be imported in ../../../nixos.nix (not yet
# wired). It supersedes the aws-vault-side workaround; once either is in place
# `aws-vault add` succeeds. Remove once oo7 lands a fix upstream.
final: prev: {
  oo7-server = prev.oo7-server.overrideAttrs (old: {
    postPatch = (old.postPatch or "") + ''
      substituteInPlace ../client/src/secret.rs \
        --replace-fail \
          'e => Err(format!("Invalid content type: {e}")),' \
          '_ => Ok(Self::Blob),'
    '';
  });
}
