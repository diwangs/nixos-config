# =====================
# seadrive-gui: pinned to stable + single-instance guard fix
# =====================
#
# PINNED TO STABLE: unstable's seadrive-fuse is `broken` ("stuck on fuse2")
# since fuse2 was removed from nixpkgs. 26.05 still builds it against fuse2, so
# seadrive-gui (whose Qt wrapper puts that seadrive-fuse on PATH) is taken from
# `pkgs-stable`. Its libfuse2 needs a setuid /run/wrappers/bin/fusermount, see
# package/nixos.nix.
#
# BUG: the "already running" guard (src/main.cpp) counts processes whose
# /proc/<pid>/exe basename is exactly "seadrive-gui". Under Nix, bin/seadrive-gui
# is a wrapQtAppsHook script exec'ing bin/.seadrive-gui-wrapped, so the guard
# never fires and a second launch starts. Each instance SIGKILLs every
# `seadrive` daemon before spawning its own (src/daemon-mgr.cpp), so the two
# GUIs kill and restart each other's daemon in a connect/disconnect loop.
# Match the wrapped binary's name instead.
#
# Drop the pin once unstable's seadrive-fuse builds on fuse3; keep the guard
# fix for as long as the package is wrapped.
{ pkgs-stable }:
final: _prev: {
  seadrive-gui = pkgs-stable.seadrive-gui.overrideAttrs (old: {
    postPatch = (old.postPatch or "") + ''
      substituteInPlace src/main.cpp --replace-fail \
        'const char *appName = "seadrive-gui";' \
        'const char *appName = ".seadrive-gui-wrapped";'
    '';
  });
}
