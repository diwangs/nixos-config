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
# The Code surface normally downloads a version-pinned Claude Code binary under
# the Electron user-data directory. We set its local-binary override to the
# packaged CLI instead, so Desktop and the terminal share the Nix patches.
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
, python3     # runtime: interpreter for Python-based Desktop Extensions (MCP)
, nodejs      # runtime: interpreter for Node-based Desktop Extensions (has a built-in fallback)
, claude-code # runtime: shared patched CLI for the Code surface and PATH users
, qemu_kvm    # runtime: qemu-system-x86_64 for Cowork's micro-VM PATH scan (host-cpu-only)

# X11
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

  # Anthropic ships a symlink in `bin/claude-desktop` to `lib/claude-desktop`.
  # Instead of wrapping the symlink, we wrap the script in `lib` directly.
  # (see fixup)
  dontWrapGApps = true;

  # Drop the bundled chrome-sandbox: it can't be setuid in the store, and a
  # NON-setuid helper present on disk makes Chromium abort ("SUID sandbox
  # helper found but not configured correctly"). Removing it lets Chromium
  # fall through to the userns sandbox
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
  # runtimeDependencies = [ "${placeholder "out"}/lib/claude-desktop" ];

  # Fixup:
  # - Wrap the `lib` entrypoint by passing the `gappsWrapperArgs`
  # - Pass necessary runtime dependencies
  # - Fix the .desktop Exec= keeping the %U and the claude:// action args
  postFixup = ''
    makeWrapper $out/lib/claude-desktop/claude-desktop $out/bin/claude-desktop \
      "''${gappsWrapperArgs[@]}" \
      --set CLAUDE_CODE_LOCAL_BINARY ${lib.getExe claude-code} \
      --prefix PATH : ${lib.makeBinPath [
        qemu_kvm    # For Cowork (host arch only, much smaller than `qemu`)
        nodejs      # Node-based Desktop extensions runtime
        python3     # Python-based Desktop extensions runtime
        xdg-utils   # For deeplink
      ]} \
      --prefix LD_LIBRARY_PATH : "${lib.makeLibraryPath [
        libglvnd    # For hw acceleration (see header comment)
        libsecret   # For signin persistence (1p only)
      ]}:${addDriverRunpath.driverLink}/lib"

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
