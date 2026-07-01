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
# --no-sandbox rationale: the .deb's postinst installs an *unconfined AppArmor
# profile* on Debian/Ubuntu so Chromium's user-namespace sandbox works under
# the modern userns restriction. We can't reproduce that from a derivation, and
# the setuid chrome-sandbox helper can't live in the (non-setuid) Nix store
# anyway. So we launch with --no-sandbox. To restore the sandbox later, expose
# chrome-sandbox via NixOS `security.wrappers` and drop the flag.
#
# GPU/rendering: at runtime the bundled Chromium logs "Could not dlopen native
# EGL: libEGL.so.1" and falls back to SwiftShader (software GL). Verified this
# is BENIGN — the app launches to a stable multi-process Wayland state and the
# same log appears with the community electron-based build. It's the libglvnd
# EGL *dispatcher* being dlopen()ed (not a NEEDED entry, so autoPatchelf can't
# see it); putting /run/opengl-driver/lib on LD_LIBRARY_PATH does NOT resolve it
# (that dir ships libEGL_mesa.so, not libEGL.so.1), so we intentionally add no
# GL env munging here. If HW acceleration is ever wanted, wrap with libglvnd +
# the addDriverRunpath driver link on LD_LIBRARY_PATH and re-verify.
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

  installPhase = ''
    runHook preInstall

    mkdir -p $out/lib/claude-desktop
    cp -r usr/lib/claude-desktop/. $out/lib/claude-desktop/

    # Icons + desktop entry.
    mkdir -p $out/share
    cp -r usr/share/icons $out/share/icons
    install -Dm644 usr/share/applications/claude-desktop.desktop \
      $out/share/applications/claude-desktop.desktop

    # The setuid sandbox helper cannot live in (or work from) the Nix store; we
    # launch with --no-sandbox instead (see header). Drop it so autoPatchelf
    # doesn't try to fix a helper we never invoke.
    rm -f $out/lib/claude-desktop/chrome-sandbox

    runHook postInstall
  '';

  # autoPatchelfHook needs to find the app-local .so's (libEGL, libGLESv2,
  # libvk_swiftshader, libvulkan.so.1) when relinking the main binary.
  runtimeDependencies = [ "${placeholder "out"}/lib/claude-desktop" ];

  postFixup = ''
    # Wrap the real Electron entrypoint: pull in the GApps env (GTK theme,
    # GSettings schemas, typelibs) from wrapGAppsHook3, force --no-sandbox, and
    # put xdg-utils on PATH for external-link / claude:// handling.
    makeWrapper $out/lib/claude-desktop/claude-desktop $out/bin/claude-desktop \
      "''${gappsWrapperArgs[@]}" \
      --prefix PATH : ${lib.makeBinPath [ xdg-utils ]} \
      --add-flags "--no-sandbox"

    # Point the .desktop Exec= at the wrapped store binary (Debian's was a bare
    # "claude-desktop" resolved via /usr/bin), keeping the %U and the claude://
    # action args intact.
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
