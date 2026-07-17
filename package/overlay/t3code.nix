# =====================
# t3code remote-SSH version fix
# =====================
#
# BUG (upstream packaging): connecting to a configured SSH host fails with
#   "cannot find t3@40.10.1"
# because t3code's desktop app builds the remote npm spec from
# `electron.app.getVersion()`:
#
#   resolveRemoteT3CliPackageSpec: return `t3@${appVersion}`   // t3@<version>
#   appVersion: electron.app.getVersion()
#
# The nixpkgs derivation launches the app by *file*
# (`electron .../dist-electron/main.cjs`) and never installs an app-root
# `package.json`. With no readable `package.json`, `getVersion()` falls back to
# reporting *Electron's own version* (e.g. 40.10.3), so the remote is told to
# `npm install t3@40.10.x`, which does not exist. (Verified empirically: a
# file-launch reports 40.10.3 regardless of any adjacent package.json; only a
# *directory* launch reads package.json and reports the real version.)
#
# FIX (two coordinated changes, appended in postInstall):
#   1. Write a package.json into dist-electron/ carrying the real version.
#   2. Re-wrap `t3code-desktop` to launch the dist-electron *directory* instead
#      of main.cjs directly. getAppPath() stays `.../dist-electron`, so no other
#      behavior changes; only getVersion() is corrected.
#
# The runtime PATH prefix (codex:gh:git) mirrors the derivation's default
# runtimePackages (enableCodex/enableGitHub/enableGit default true). Keep this
# in sync if those enable flags are ever overridden.
#
# Standalone overlay: import in ../../nixos.nix. Remove once nixpkgs
# ships an app-root package.json for t3code.
final: prev:
let
  lib = final.lib;
in
{
  t3code = prev.t3code.overrideAttrs (old: {
    postInstall = (old.postInstall or "") + ''
      desktop="$out/libexec/t3code/apps/desktop/dist-electron"

      # (1) app-root package.json so electron.app.getVersion() reports the real
      # t3code version instead of Electron's.
      echo '{"name":"t3code","version":"${old.version}","main":"main.cjs"}' \
        > "$desktop/package.json"

      # (2) re-wrap to launch the directory (file-launch ignores package.json).
      rm "$out/bin/t3code-desktop"
      makeWrapper ${lib.getExe final.electron_40} "$out/bin/t3code-desktop" \
        --add-flags "$desktop" \
        --inherit-argv0 \
        --prefix PATH : ${lib.makeBinPath [ final.codex final.gh final.git ]}
    '';
  });
}
