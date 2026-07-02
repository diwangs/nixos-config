# Official Claude Desktop for Linux (beta), repackaged from Anthropic's Debian
# .deb — https://code.claude.com/docs/en/desktop-linux
#
# Anthropic ships this ONLY as a .deb through their apt repo. The .deb is a
# stock Electron bundle laid out for the FHS: a prebuilt Electron binary at
# /usr/lib/claude-desktop/claude-desktop linked against the Debian dynamic
# loader + system libs, an app.asar next to it, and two native node addons
# under app.asar.unpacked (claude-native, node-pty). We unpack it and let
# autoPatchelfHook rewrite the ELF interpreter/rpaths of the Electron binary,
# the bundled .so's, and the .node addons into the Nix store; wrapGAppsHook3
# supplies the GTK/GIO/GSettings-schema + typelib env at runtime.
#
# This derivation is deliberately FAITHFUL to the official build: no app.asar
# patching, no claude-code wiring, no portal/screenshot deps. (Computer Use
# isn't in the Linux beta, and the app bundles its own Cowork backend.) It is
# the counterpart to ../claude-desktop-bin (the community patrickjaja build);
# only one should inject `claude-desktop` at a time — see ../../nixos.nix.
#
# GPU/rendering: HW acceleration is ON. Chromium `dlopen`s the glvnd dispatcher
# soname `libEGL.so.1`, which is a NEEDED-less runtime load (so autoPatchelf
# can't wire it) and is present in NONE of the obvious places: the bundle ships
# only ANGLE's sonameless `libEGL.so`, and /run/opengl-driver/lib ships the mesa
# *vendor* impl `libEGL_mesa.so` — neither has the `.1` soname. The dispatcher
# lives in `libglvnd`. So the postFixup wrapper prefixes LD_LIBRARY_PATH with
# `${libglvnd}/lib` (provides libEGL.so.1 / libGLESv2.so.2 / libGLX.so.0) AND
# `${addDriverRunpath.driverLink}/lib` (= /run/opengl-driver/lib: mesa vendor
# impls + dri/ + gbm/). Once libEGL.so.1 loads, glvnd finds the real driver via
# its EGL vendor JSON: NixOS' libglvnd hardcodes /run/opengl-driver/share/glvnd/
# egl_vendor.d, whose 50_mesa.json points at libEGL_mesa.so.0 by absolute store
# path — so the chain to this box's AMD radeonsi driver resolves automatically,
# no Chromium GL flags needed. Without accel Chromium logged "Could not dlopen
# native EGL: libEGL.so.1" and ran the gpu-process with --use-gl=disabled
# (SwiftShader software GL); the community electron build showed the same log.
#
# NOTE: on hardened kernel, make sure to either enable unprivileged user NS or
# disable Chromium sandbox.
#
# Version + hash are PINNED below and maintained by ./update.sh — do not edit
# the two UPDATE MARKER lines by hand.
#
# Last updated: 010726
{ lib
, stdenv
, fetchurl
, dpkg
, autoPatchelfHook
, makeWrapper
, wrapGAppsHook3
, addDriverRunpath  # .driverLink = /run/opengl-driver (HW GL/Vulkan driver path)
, # runtime libs — from the .deb's `Depends` mapped to nixpkgs, plus the usual
  # Electron/Chromium shared-object closure that autoPatchelfHook resolves.
  glib
, gtk3
, nss
, nspr
, at-spi2-atk
, at-spi2-core
, atk
, cairo
, pango
, gdk-pixbuf
, expat
, dbus
, cups
, libdrm
, libgbm
, mesa
, libGL
, libglvnd
, libsecret
, libnotify
, libuuid
, libxkbcommon
, alsa-lib
, systemd     # libudev (autoPatchelf), and libsystemd
, libseccomp  # bundled virtiofsd (Cowork VM helper)
, libcap_ng   # bundled virtiofsd (Cowork VM helper)
, xdg-utils   # runtime: xdg-open for external links / claude:// scheme
, libx11
, libxcb
, libxcomposite
, libxdamage
, libxext
, libxfixes
, libxrandr
, libxrender
, libxtst
, libxi
, libxscrnsaver
, libxshmfence
}:

stdenv.mkDerivation (finalAttrs: {
  pname = "claude-desktop";
  version = "1.17377.1"; # UPDATE MARKER: version

  src = fetchurl {
    url = "https://downloads.claude.ai/claude-desktop/apt/stable/pool/main/c/claude-desktop/claude-desktop_${finalAttrs.version}_amd64.deb";
    hash = "sha256-9L14VFIAh3tZEXmDjeeteld99u0uhFlp3SVpDvxchcc="; # UPDATE MARKER: hash
  };

  nativeBuildInputs = [
    dpkg
    autoPatchelfHook
    makeWrapper
    wrapGAppsHook3
  ];

  buildInputs = [
    glib
    gtk3
    nss
    nspr
    at-spi2-atk
    at-spi2-core
    atk
    cairo
    pango
    gdk-pixbuf
    expat
    dbus
    cups
    libdrm
    libgbm
    mesa
    libGL
    libglvnd
    libsecret
    libnotify
    libuuid
    libxkbcommon
    alsa-lib
    systemd
    libseccomp
    libcap_ng
    libx11
    libxcb
    libxcomposite
    libxdamage
    libxext
    libxfixes
    libxrandr
    libxrender
    libxtst
    libxi
    libxscrnsaver
    libxshmfence
  ];

  unpackCmd = "dpkg-deb -x $src .";
  sourceRoot = ".";

  dontConfigure = true;
  dontBuild = true;

  # wrapGAppsHook3 would wrap $out/bin/* automatically, but the launcher we want
  # to wrap is the Electron binary deep in lib/. Do the wrapping by hand in
  # postFixup (after autoPatchelf) and let the gappsWrapperArgs flow in via
  # --prefix, so defer the hook's own wrapping.
  dontWrapGApps = true;

  # Drop the bundled chrome-sandbox: it can't be setuid in the store, and a
  # NON-setuid helper present on disk makes Chromium abort ("SUID sandbox
  # helper found but not configured correctly"). Removing it lets Chromium
  # fall through to the userns sandbox (see header); also spares autoPatchelf
  # a helper we never invoke.
  installPhase = ''
    runHook preInstall

    mkdir -p $out/lib/claude-desktop
    cp -r usr/lib/claude-desktop/. $out/lib/claude-desktop/

    # Icons + desktop entry.
    mkdir -p $out/share
    cp -r usr/share/icons $out/share/icons
    install -Dm644 usr/share/applications/claude-desktop.desktop \
      $out/share/applications/claude-desktop.desktop

    rm -f $out/lib/claude-desktop/chrome-sandbox

    runHook postInstall
  '';

  # autoPatchelfHook needs to find the app-local .so's (libEGL, libGLESv2,
  # libvk_swiftshader, libvulkan.so.1) when relinking the main binary.
  runtimeDependencies = [ "${placeholder "out"}/lib/claude-desktop" ];

  # Wrap the real Electron entrypoint: pull in the GApps env (GTK theme,
  # GSettings schemas, typelibs) from wrapGAppsHook3, and put xdg-utils on
  # PATH for external-link / claude:// handling. No --no-sandbox: the userns
  # sandbox is kept on (see header).
  #
  # LD_LIBRARY_PATH: libglvnd (the EGL/GLES/GLX dispatchers, incl. the
  # libEGL.so.1 Chromium dlopen()s) + the HW driver link, to enable GPU
  # acceleration (see the GPU/rendering note in the header). --prefix (not
  # --set) so any LD_LIBRARY_PATH from gappsWrapperArgs is preserved; it's
  # scoped to this launcher and inherited by the Electron gpu/renderer children.
  #
  # Point the .desktop Exec= at the wrapped store binary (Debian's was a bare
  # "claude-desktop" resolved via /usr/bin), keeping the %U and the claude://
  # action args intact.
  postFixup = ''
    makeWrapper $out/lib/claude-desktop/claude-desktop $out/bin/claude-desktop \
      "''${gappsWrapperArgs[@]}" \
      --prefix PATH : ${lib.makeBinPath [ xdg-utils ]} \
      --prefix LD_LIBRARY_PATH : "${lib.makeLibraryPath [ libglvnd ]}:${addDriverRunpath.driverLink}/lib"

    substituteInPlace $out/share/applications/claude-desktop.desktop \
      --replace-warn 'Exec=claude-desktop' "Exec=$out/bin/claude-desktop"
  '';

  meta = {
    description = "Official desktop application for Claude.ai (repackaged from Anthropic's .deb)";
    homepage = "https://claude.ai";
    downloadPage = "https://claude.com/download";
    changelog = "https://code.claude.com/docs/en/desktop-linux";
    license = lib.licenses.unfree;
    sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
    platforms = [ "x86_64-linux" ];
    mainProgram = "claude-desktop";
  };
})
