# Patch overlay: make Cowork's QEMU sandbox VM work on NixOS.
#
# Layered on top of ../package.nix (the faithful base). Import AFTER ../overlay.nix
# in nixos.nix; it commutes with the sibling patches (each does its own
# extract→repack via ./lib.nix's mkAsarPatch). Keeping the asar rewrites out of
# package.nix preserves the base as a 1:1 repackage of Anthropic's .deb.
#
# Why it's needed: Cowork can run tasks in a lightweight QEMU micro-VM. On
# startup the app (a content-hashed `.vite/build/index.chunk-*.js` — resolved at
# build time via helpers.findChunk, see ./lib.nix) resolves three deps and
# reports the feature "unsupported" if any is missing:
#   - qemu-system-x86_64 : found via a $PATH scan → handled by the system
#     (aspect/virtualisation.nix puts qemu on PATH). NOT patched here.
#   - OVMF firmware      : looked up ONLY at the hardcoded absolute paths
#     ["/usr/share/OVMF/OVMF_CODE_4M.fd","/usr/share/OVMF/OVMF_CODE.fd"] — no
#     env override, never joined with resourcesPath. Doesn't exist on NixOS.
#   - virtiofsd          : ["/usr/libexec/virtiofsd","/usr/bin/virtiofsd"], and
#     the copy bundled in the .deb is only used as a fallback when the OS looks
#     like Ubuntu 22 (`(await osRelease).id==="ubuntu" && versionId.startsWith
#     ("22.")`) — false on NixOS, so the bundled binary is never picked.
# So both absolute-path lists must point into the Nix store. The app derives the
# writable VARS template from the CODE path via `.replace("OVMF_CODE",
# "OVMF_VARS")`; nixpkgs' OVMF ships OVMF_CODE.fd + OVMF_VARS.fd side-by-side in
# $out/FV and the store path contains "OVMF_CODE" exactly once (the filename),
# so that derivation resolves correctly — verified.
#
# Both target string literals occur exactly once in the bundle (verified), so
# the substitutions are unambiguous. We still use `--replace-warn` (not -fail):
# an upstream minified-anchor drift then degrades this one feature with a
# visible build-log warning instead of breaking the whole nixos-rebuild — same
# policy as ../../claude-desktop-bin. KVM/vsock device access is a separate,
# system-level gate handled by the virtualisation aspect.
#
# NOTE: this is x86 only. ARM depends on another line.
final: prev:
let
  helpers = import ./lib.nix { inherit (final) lib; };
  ovmfCode = "${final.OVMF.fd}/FV/OVMF_CODE.fd"; # $out/FV/{OVMF_CODE,OVMF_VARS}.fd
  virtiofsd = "${final.virtiofsd}/bin/virtiofsd";
in
{
  claude-desktop = prev.claude-desktop.overrideAttrs (old: {
    nativeBuildInputs = (old.nativeBuildInputs or [ ]) ++ [ final.asar ];

    postInstall =
      (old.postInstall or "")
      + "\n"
      + helpers.mkAsarPatch {
        label = "cowork-vm FHS paths (OVMF + virtiofsd)";
        body = ''
          target=${helpers.findChunk "/usr/libexec/virtiofsd"}
          if [ -n "$target" ]; then
            substituteInPlace "$target" \
              --replace-warn \
                '["/usr/share/OVMF/OVMF_CODE_4M.fd","/usr/share/OVMF/OVMF_CODE.fd"]' \
                '["${ovmfCode}"]' \
              --replace-warn \
                '["/usr/libexec/virtiofsd","/usr/bin/virtiofsd"]' \
                '["${virtiofsd}"]'
          else
            echo "[claude-desktop patch] cowork-vm: anchor chunk not found; skipping (feature degraded, per warn policy)"
          fi
        '';
      };
  });
}
