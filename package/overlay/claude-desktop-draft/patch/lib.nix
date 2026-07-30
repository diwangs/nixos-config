# Draft-specific plumbing shared by the patch fragments in THIS directory.
#
# WHY IT EXISTS: the draft packaging wraps the app in buildFHSEnv, so the
# derivation bound to `claude-desktop` is a thin symlink to the FHS launcher and
# has NO lib/claude-desktop/resources/app.asar to patch. The app.asar lives in
# the inner `passthru.unwrapped`. So every fragment has to:
#   1. patch `unwrapped` (asarRoot is $out/lib/claude-desktop/resources, same as
#      the base build — ../../claude-desktop/patch/lib.nix's `mkAsarPatch` works
#      unchanged), then
#   2. rebuild the FHS wrapper + top-level symlinks around the patched
#      `unwrapped`, because `fhsEnv` captured the original by store path and has
#      no `.override` to swap it.
#
# `mkPatch` does both, so the step-2 boilerplate is written exactly once instead
# of copy-pasted into each fragment.
#
# The `fhsEnv` block below MIRRORS ../package.nix's `fhsEnv`. It is the concrete
# cost of the FHS restructuring for the patch-overlay architecture: if pull.sh
# brings in upstream changes to that block, RE-SYNC it here. (x86_64 only — the
# upstream aarch64 AAVMF branch is dropped; this host is x86_64-linux.)
#
# COMPOSITION: fragments stay order-independent the same way the base ones do.
# Each `mkPatch` appends to `prev.claude-desktop.unwrapped`'s postFixup — which,
# for the second and later fragments, is already the previous fragment's patched
# `unwrapped` — and then re-wraps. The last fragment in the import list wins the
# wrapper rebuild, and by then `unwrapped` carries every fragment's patch.
{ final, prev }:
{
  # mkPatch: turn a bash snippet that mutates the UNWRAPPED output tree into a
  # complete overlay attrset. `postFixup` runs after ../package.nix's own
  # postFixup (Cowork VM asar rewrite + wrapProgram), typically wrapping a
  # ../../claude-desktop/patch/lib.nix `mkAsarPatch` / `mkLoosePatch` body.
  mkPatch =
    { postFixup }:
    let
      patchedUnwrapped = prev.claude-desktop.unwrapped.overrideAttrs (old: {
        nativeBuildInputs = (old.nativeBuildInputs or [ ]) ++ [ final.asar ];
        postFixup = (old.postFixup or "") + "\n" + postFixup;
      });

      fhsEnv = final.buildFHSEnv {
        pname = "claude-desktop-fhsenv";
        inherit (patchedUnwrapped) version;

        targetPkgs =
          pkgs: with pkgs; [
            patchedUnwrapped
            glibc
            qemu_kvm
            python3
            nodejs
            libsecret
            libglvnd
            mesa
            virtiofsd
            git
            openssh
            procps
          ];

        extraBuildCommands = ''
          ### OVMF firmware
          mkdir -p "$out/usr/share/OVMF"
          ln -s ${final.OVMF.fd}/FV/OVMF_CODE.fd  "$out/usr/share/OVMF/OVMF_CODE.fd"
          ln -s ${final.OVMF.fd}/FV/OVMF_CODE.fd  "$out/usr/share/OVMF/OVMF_CODE_4M.fd"
          ln -s ${final.OVMF.fd}/FV/OVMF_VARS.fd  "$out/usr/share/OVMF/OVMF_VARS.fd"
          ln -s ${final.OVMF.fd}/FV/OVMF_VARS.fd  "$out/usr/share/OVMF/OVMF_VARS_4M.fd"

          ### virtiofsd fallback paths
          mkdir -p "$out/usr/libexec" "$out/usr/bin"
          ln -sf ${final.virtiofsd}/bin/virtiofsd "$out/usr/libexec/virtiofsd"
          ln -sf ${final.virtiofsd}/bin/virtiofsd "$out/usr/bin/virtiofsd"

          ### Absolute-path helpers some app code still probes under /usr/bin
          mkdir -p "$out/usr/bin"
          ln -sf ${final.lib.getExe final.git} "$out/usr/bin/git"
          ln -sf ${final.openssh}/bin/ssh "$out/usr/bin/ssh"
          ln -sf ${final.procps}/bin/pgrep "$out/usr/bin/pgrep"
        '';

        extraBwrapArgs = [
          "--dev-bind-try /dev/kvm /dev/kvm"
          "--dev-bind-try /dev/vhost-vsock /dev/vhost-vsock"
          "--dev-bind-try /dev/vhost-net /dev/vhost-net"
          "--dev-bind-try /dev/net/tun /dev/net/tun"
        ];

        extraInstallCommands = ''
          mkdir -p "$out/share"
          ln -s ${patchedUnwrapped}/share/* "$out/share/"
        '';

        runScript = "${patchedUnwrapped}/bin/claude-desktop";

        ### Avoid orphaned Electron after the launcher / nix run exits
        dieWithParent = true;
      };
    in
    {
      # Re-point the top-level symlinks at the rebuilt wrapper, and expose the
      # patched `unwrapped`/`fhsEnv` through passthru.
      claude-desktop = prev.claude-desktop.overrideAttrs (old: {
        installPhase = ''
          mkdir -p "$out/bin" "$out/share"
          ln -s ${fhsEnv}/bin/claude-desktop-fhsenv "$out/bin/claude-desktop"
          ln -s ${fhsEnv}/share/* "$out/share/"
        '';
        passthru = (old.passthru or { }) // {
          unwrapped = patchedUnwrapped;
          inherit fhsEnv;
        };
      });
    };
}
