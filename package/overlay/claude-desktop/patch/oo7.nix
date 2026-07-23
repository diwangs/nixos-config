# Work around oo7's broken Secret Portal handling for Chromium.
# ashpd can panic on Chromium's digit-leading portal token without replying;
# OSCrypt then blocks persistent-cookie startup indefinitely.
final: prev: {
  claude-desktop = prev.claude-desktop.overrideAttrs (old: {
    postFixup = (old.postFixup or "") + ''
      substituteInPlace $out/share/applications/com.anthropic.Claude.desktop \
        --replace-fail "Exec=$out/bin/claude-desktop" \
          "Exec=$out/bin/claude-desktop --disable-features=DbusSecretPortal"
    '';
  });
}
