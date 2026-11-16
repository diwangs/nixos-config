{
  hermes-agent,
  lib,
  patchelfUnstable,
  pkgs,
  stdenv,
  writeShellScriptBin,
}:
let
  system = stdenv.hostPlatform.system;

  # Upstream's desktop derivation requires a Hermes Agent package and writes
  # its executable into the launcher as HERMES_DESKTOP_HERMES. Supply a tiny
  # build-time stand-in, then remove that launcher setting below. This lets us
  # reuse the maintained Electron/native-module build without retaining the
  # full Python agent or offering it to the app as a local backend.
  hermes-placeholder = writeShellScriptBin "hermes" ''
    echo "Hermes Agent is not installed by this desktop-only package." >&2
    exit 1
  '';

  # Upstream autoPatchelfs its pm/lock.json tools (node, pnpm, ...) with
  # nixpkgs' `patchelf` plus NixOS/patchelf#672, a fix for headers moved into
  # an overlapping LOAD segment that makes node segfault before main. That
  # patch targets 0.19.x, but our nixpkgs' `patchelf` is 0.15.2, where it does
  # not apply. `patchelfUnstable` already contains the fix, so hand it over
  # with its overrideAttrs neutralised to keep the patch from applying twice.
  # Drop this once nixpkgs' `patchelf` is a release containing #672.
  hermesPatchelf = patchelfUnstable // {
    overrideAttrs = _: patchelfUnstable;
  };

  # Mirrors pmPackages and hermesNpmLib in upstream's nix/packages.nix and
  # nix/hermes-agent.nix, differing only in the patchelf above.
  hermesPmPackages = lib.filterAttrs (_: lib.isDerivation) (
    pkgs.callPackage "${hermes-agent}/nix/pm-packages.nix" {
      patchelf = hermesPatchelf;
    }
  );
  hermesNpmLib = pkgs.callPackage "${hermes-agent}/nix/lib.nix" {
    pmPackages = hermesPmPackages;
  };

  upstream = hermes-agent.packages.${system}.desktop.override {
    inherit hermesNpmLib;
    hermesAgent = hermes-placeholder;
    extraEnv.HERMES_DESKTOP_PASSWORD_STORE = "gnome-libsecret";
  };
in
upstream.overrideAttrs (oldAttrs: {
  pname = "hermes-desktop";

  postInstall = (oldAttrs.postInstall or "") + ''
    launcher="$out/bin/hermes-desktop"

    if [ "$(grep -c 'HERMES_DESKTOP_HERMES' "$launcher")" -ne 1 ]; then
      echo "Expected exactly one upstream HERMES_DESKTOP_HERMES launcher setting." >&2
      exit 1
    fi
    sed -i '/HERMES_DESKTOP_HERMES/d' "$launcher"

    if grep -R -F -q -- ${lib.escapeShellArg (toString hermes-placeholder)} "$out"; then
      echo "The desktop output still refers to the Hermes Agent placeholder." >&2
      exit 1
    fi
  '';
})
