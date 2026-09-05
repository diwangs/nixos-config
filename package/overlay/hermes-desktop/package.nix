{
  hermes-agent,
  electron,
  lib,
  pkgs,
  runCommandLocal,
  stdenv,
  writeShellScriptBin,
}:
let
  system = stdenv.hostPlatform.system;

  # Hermes fetches an Electron headers archive with a hash pinned to the
  # Electron version in its own nixpkgs lock. Repack nixpkgs' matching,
  # already-fetched headers so the upstream build follows our Electron update
  # without maintaining a second version/hash table here.
  electronHeadersArchive =
    runCommandLocal "electron-${electron.version}-headers.tar.gz" { }
      ''
        tar -C ${electron.headers} -czf "$out" .
      '';

  electronHeadersUrl = "https://artifacts.electronjs.org/headers/dist/v${electron.version}/node-v${electron.version}-headers.tar.gz";

  hermesPkgs = pkgs // {
    fetchurl =
      args:
      if args.url == electronHeadersUrl then
        electronHeadersArchive
      else
        pkgs.fetchurl args;
  };

  # Upstream's desktop derivation requires a Hermes Agent package and writes
  # its executable into the launcher as HERMES_DESKTOP_HERMES. Supply a tiny
  # build-time stand-in, then remove that launcher setting below. This lets us
  # reuse the maintained Electron/native-module build without retaining the
  # full Python agent or offering it to the app as a local backend.
  hermes-placeholder = writeShellScriptBin "hermes" ''
    echo "Hermes Agent is not installed by this desktop-only package." >&2
    exit 1
  '';

  upstream = hermes-agent.packages.${system}.desktop.override {
    pkgs = hermesPkgs;
    inherit electron;
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
