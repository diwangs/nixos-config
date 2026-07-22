# =====================
# aws-vault × oo7 secret-service content-type fix
# =====================
#
# BUG: `aws-vault add` fails with
#   aws-vault: error: add: Invalid content type: application/json
# after migrating the Secret Service backend from gnome-keyring to oo7
# (see aspect/secret.hm.nix). The error string is NOT in aws-vault; it is a
# D-Bus error returned by oo7-daemon, which now owns org.freedesktop.secrets.
#
# ROOT CAUSE (two-sided):
#   * aws-vault's keyring lib (github.com/byteness/keyring, a 99designs/keyring
#     fork) json.Marshal's each item and hardcodes the Secret's content-type to
#     "application/json" (secretservice.go: NewSecret(..., data, "application/json")).
#   * oo7 collapses the Secret Service's free-form `content_type` string into a
#     two-variant enum and REJECTS anything outside its whitelist
#     (client/src/secret.rs ContentType::from_str: only text/plain, text/utf8,
#     application/octet-stream are accepted; everything else -> Err). This is
#     stricter than the spec, which documents content_type as a free-form MIME
#     string. gnome-keyring stored it verbatim, so this worked before.
#
# FIX: relabel the write to "text/plain". The payload is json.Marshal output
# (always valid UTF-8), so oo7's Text bucket (String::from_utf8) round-trips it
# losslessly; the keyring read path json.Unmarshal's secret.Value and ignores
# the content-type entirely, so this is fully back/forward compatible. This is
# a local relabel workaround; the real defect is oo7's whitelist rejecting a
# legal content-type (worth reporting upstream to bilelmoussaoui/oo7).
#
# MECHANICS: the nixpkgs derivation uses `proxyVendor = true` (deps served from
# a module-proxy FOD, no vendor/ tree to patch). Flip to `proxyVendor = false`
# so buildGoModule materializes a writable vendor/ tree (see
# pkgs/build-support/go/module.nix configurePhase: cp -r "$goModules" vendor),
# then substitute the one string in postConfigure. Switching proxyVendor
# changes the vendored layout, hence a fresh vendorHash.
#
# Standalone overlay: imported in ../../nixos.nix only. aws-vault is a
# laptop-only package (moved out of the shared package/home-manager.devbox.nix
# into package/home-manager.nix), so devbox homeConfigurations never see it and
# need no wiring. Remove once byteness/keyring or oo7 lands a fix upstream.
final: prev: {
  aws-vault = prev.aws-vault.overrideAttrs (old: {
    # Materialize a real vendor/ tree instead of a GOPROXY dir so postConfigure
    # can patch a dependency file. This changes the vendorHash.
    proxyVendor = false;
    vendorHash = "sha256-HLB9TTnplzW4wcOSHOTG+mcU/Of1KJMlNUr05unChdM=";

    postConfigure = (old.postConfigure or "") + ''
      # cp -r from the read-only FOD preserves 0444, so make it writable first.
      chmod -R u+w vendor
      substituteInPlace vendor/github.com/byteness/keyring/secretservice.go \
        --replace-fail '"application/json"' '"text/plain"'
    '';
  });
}
