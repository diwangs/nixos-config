{
  lib,
  callPackage,
  stdenv,
  stdenvNoCC,
  fetchurl,
  unzip,
  autoPatchelfHook,
  dpkg,
  makeWrapper,
  wrapGAppsHook3,
  alsa-lib,
  at-spi2-atk,
  at-spi2-core,
  atk,
  cairo,
  cups,
  dbus,
  expat,
  gdk-pixbuf,
  glib,
  gtk3,
  libgbm,
  libGL,
  libnotify,
  libpulseaudio,
  libsecret,
  libusb1,
  libx11,
  libxcb,
  libxcomposite,
  libxdamage,
  libxext,
  libxfixes,
  libxkbcommon,
  libxrandr,
  nspr,
  nss,
  pango,
  pipewire,
  qt6,
  systemdLibs,
  tectonic-unwrapped,
  vulkan-loader,
  xdg-utils,
}:
stdenvNoCC.mkDerivation (finalAttrs: {
  pname = "chatgpt";
  inherit (finalAttrs.passthru.source) version;

  src = fetchurl finalAttrs.passthru.source.src;

  strictDeps = true;
  __structuredAttrs = true;

  nativeBuildInputs =
    lib.optionals stdenvNoCC.hostPlatform.isDarwin [ unzip ]
    ++ lib.optionals stdenvNoCC.hostPlatform.isLinux [
      autoPatchelfHook
      dpkg
      makeWrapper
      qt6.wrapQtAppsHook
      wrapGAppsHook3
    ];

  buildInputs = lib.optionals stdenvNoCC.hostPlatform.isLinux [
    (lib.getLib stdenv.cc.cc)
    alsa-lib
    at-spi2-atk
    at-spi2-core
    atk
    cairo
    cups
    dbus
    expat
    gdk-pixbuf
    glib
    gtk3
    libgbm
    libnotify
    libusb1
    libx11
    libxcb
    libxcomposite
    libxdamage
    libxext
    libxfixes
    libxkbcommon
    libxrandr
    nspr
    nss
    pango
    qt6.qtbase
    systemdLibs
  ];

  autoPatchelfIgnoreMissingDeps = lib.optionals stdenvNoCC.hostPlatform.isLinux [
    "libQt5Core.so.5"
    "libQt5Gui.so.5"
    "libQt5Widgets.so.5"
    "libc.musl-*.so.1"
    # Android prebuilds are not used by the desktop app.
    "libc++_shared.so"
    "liblog.so"
  ];

  dontWrapGApps = true;
  dontWrapQtApps = true;

  sourceRoot = if stdenvNoCC.hostPlatform.isLinux then "root" else ".";

  installPhase = ''
    runHook preInstall
  ''
  + lib.optionalString stdenvNoCC.hostPlatform.isDarwin ''
    mkdir -p "$out/Applications"
    mkdir -p "$out/bin"
    cp -a ChatGPT.app "$out/Applications"
    ln -s "$out/Applications/ChatGPT.app/Contents/MacOS/ChatGPT" "$out/bin/ChatGPT"
  ''
  + lib.optionalString stdenvNoCC.hostPlatform.isLinux ''
    mkdir -p "$out"
    cp -r usr/* "$out"

    # The bundled Tectonic has an invalid section table and patchelf fails to fix it.
    rm "$out/lib/chatgpt/resources/plugins/openai-bundled/plugins/latex/bin/tectonic"
    ln -s ${lib.getExe tectonic-unwrapped} \
      "$out/lib/chatgpt/resources/plugins/openai-bundled/plugins/latex/bin/tectonic"

    rm "$out/bin/chatgpt"
    makeWrapper ${lib.getExe (callPackage ./launcher.nix { })} "$out/bin/chatgpt" \
      "''${gappsWrapperArgs[@]}" \
      "''${qtWrapperArgs[@]}" \
      --set CHATGPT_EXECUTABLE "$out/lib/chatgpt/ChatGPT" \
      --set CHATGPT_RESOURCES_SOURCE "$out/lib/chatgpt/resources" \
      --set CHATGPT_RESOURCES_CACHE_KEY ${lib.escapeShellArg "${finalAttrs.version}-${stdenvNoCC.hostPlatform.system}"} \
      --prefix LD_LIBRARY_PATH : ${
        lib.makeLibraryPath [
          libGL
          libnotify
          libpulseaudio
          libsecret
          pipewire
          vulkan-loader
        ]
      } \
      --prefix PATH : ${lib.makeBinPath [ xdg-utils ]} \
      --add-flags "\''${NIXOS_OZONE_WL:+\''${WAYLAND_DISPLAY:+--ozone-platform-hint=auto --enable-features=WaylandWindowDecorations --enable-wayland-ime=true}}"
  ''
  + ''
    runHook postInstall
  '';

  dontStrip = true;

  passthru = {
    updateScript = ./update.sh;
    sources = import ./source.nix;
    source =
      finalAttrs.passthru.sources.${stdenvNoCC.hostPlatform.system}
        or (throw "chatgpt is not supported on ${stdenvNoCC.hostPlatform.system}");
  };

  meta = {
    description = "Desktop application for ChatGPT";
    homepage = "https://openai.com/chatgpt/desktop/";
    changelog = "https://learn.chatgpt.com/docs/changelog";
    license = lib.licenses.unfree;
    maintainers = with lib.maintainers; [
      wattmto
      moraxyc
    ];
    platforms = lib.attrNames finalAttrs.passthru.sources;
    sourceProvenance = with lib.sourceTypes; [ binaryNativeCode ];
    mainProgram = if stdenvNoCC.hostPlatform.isDarwin then "ChatGPT" else "chatgpt";
  };
})
