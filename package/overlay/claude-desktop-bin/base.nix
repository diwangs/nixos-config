# Claude Desktop 3p (OpenRouter): BASE construction overlay.
#
# This overlay only CONSTRUCTS `claude-desktop`; the behavioral patches live in
# ./patches/*.nix and are layered as separate, independent overlays (see below
# and ../../nixos.nix). Import this one FIRST, then any subset of the patches.
#
# Base: github:patrickjaja/claude-desktop-bin. Unlike aaddrick's flake, it
# exposes NO `overlays.default` — only `packages.claude-desktop`, built by
# `packaging/nix/package.nix` from a CI-prebuilt, already-Linux-patched release
# tarball. So we construct `claude-desktop` ourselves via `callPackage` (against
# our `final` pkgs), wiring in `claude-code` so its Cowork/Code integration
# resolves the CLI on NixOS (upstream defaults it to null and only greps
# /usr/bin, ~/.local/bin, /usr/local/bin, `which`). `asar` is not in their build
# inputs, so we add it here — every patch overlay needs it for extract/repack.
#
# Our patches run AGAINST their already-patched app.asar. Verified there are no
# textual conflicts with their ~42 patches; residual risk is upstream version
# drift of the minified anchors, so every substitution uses `--replace-warn`
# (NOT `--replace-fail`): a drifted anchor degrades that one surface gracefully
# and is visible in the build log, instead of breaking the whole nixos-rebuild.
# The tradeoff: a silent no-op must be caught by per-surface runtime checks.
#
# Problem the patches solve: OpenRouter has a different model ID than Anthropic
# 1p, which broke effort selection, the thinking toggle, and 1m-context
# selection across Chat, Cowork, and Code; plus Computer Use was gated off and
# mis-clicked on Wayland. The fix is a set of small, INDEPENDENT patch overlays
# — one file each under ./patches. Each fragment runs its own complete extract →
# substituteInPlace → repack cycle (see ./lib.nix), so the patch overlays
# commute: add, remove, or reorder their imports in ../../nixos.nix freely. The
# numeric filename prefixes are for human readability only, not ordering
# significance. See each ./patches/*.nix for the per-patch rationale.
{ claude-desktop-bin }:
(final: prev:
let
  # --- Computer Use screenshots on GNOME Wayland: force the portal+PipeWire path ---
  #
  # The executor's screenshot cascade (in app.asar `_captureRegion`) tries, in
  # order: grim (wlroots) -> portal+PipeWire IF a restore-token exists ->
  # gnome-screenshot -> gdbus ScreenshotArea -> portal+PipeWire (first-run, no
  # token) -> ... . On GNOME Wayland the only branches that ever gate true are
  # the gnome-screenshot one and the two portal ones.
  #
  # Two problems on GNOME 50 + this XWayland setup (the app runs with
  # --ozone-platform=x11; see desktop.nix CLAUDE_USE_XWAYLAND):
  #
  #   1. gnome-screenshot (v41) captures by calling the legacy
  #      `org.gnome.Shell.Screenshot` D-Bus interface, which GNOME 50 restricts
  #      to allowlisted callers UNLESS `global.context.unsafe_mode` is true.
  #      With unsafe_mode off (the default, reset on every Shell restart) the
  #      call is AccessDenied, gnome-screenshot falls back to grabbing the X11
  #      root — which under XWayland Mutter never paints — so the capture is a
  #      solid-black image. Captures only "worked" before because unsafe_mode
  #      had been left on manually; a reboot exposed the latent dependency.
  #
  #   2. The portal+PipeWire branch (`_portalScreenshot`: a python3-gi script
  #      driving `org.freedesktop.portal.ScreenCast` -> pipewiresrc) is the
  #      idiomatic, XWayland-proof path — Mutter composites server-side and
  #      streams the pixels over a PipeWire fd, so the app's render backend is
  #      irrelevant. But it is gated on `_hasPortalDeps() = _hasCmd("python3")
  #      && _hasCmd("gst-launch-1.0")`, and the launcher's PATH had python3 but
  #      NOT gst-launch-1.0 — so the branch was silently skipped.
  #
  # Fix = make the portal branch both REACHABLE and FUNCTIONAL:
  #   (a) Remove gnome-screenshot from the launcher PATH (`gnome-screenshot =
  #       null`). It sits BEFORE the first-run portal branch and "succeeds"
  #       (exit 0 + black file; `_readClean` does no validation), so leaving it
  #       in shadows the portal branch forever. Removing it lets the cascade
  #       fall through to portal+PipeWire. (gnome-screenshot is only on the
  #       launcher PATH via this wrapper, not system-wide, so dropping it here
  #       fully removes it for the app.)
  #   (b) Add the portal deps via extraSessionPaths: a python3 (with pygobject3
  #       / `gi`) and gst-launch-1.0, plus — scoped onto that python3 wrapper so
  #       nothing leaks into the global app env — the GI typelibs (Gst, GLib,
  #       GdkPixbuf) and the GStreamer plugins the pipeline needs (pipewiresrc
  #       from pipewire, videoconvert/pngenc from base/good, filesink from
  #       core). Verified end-to-end: this yields a real 2560x1440 capture of
  #       the primary monitor (vs the ~1.4 KB black image from gnome-screenshot).
  #
  # Once the first portal run mints a restore-token (~/.config/Claude-3p/
  # pipewire-restore-token), the token-gated portal branch — which is BEFORE
  # gnome-screenshot anyway — wins on every subsequent capture, prompt-free.
  gst = final.gst_all_1;
  cuPortalTypelibs = final.lib.makeSearchPath "lib/girepository-1.0" [
    final.glib.out          # GLib / Gio / GObject
    gst.gstreamer.out       # Gst core typelib
    final.gdk-pixbuf.out    # GdkPixbuf (the script's crop fallback)
  ];
  cuPortalGstPlugins = final.lib.makeSearchPath "lib/gstreamer-1.0" [
    gst.gstreamer.out       # coreelements (filesink)
    gst.gst-plugins-base    # videoconvert
    gst.gst-plugins-good    # pngenc
    final.pipewire          # pipewiresrc (libgstpipewire.so)
  ];
  # python3 wrapper that exports the GI/GStreamer search paths for itself only,
  # so the executor's `python3 -` portal script can `import gi; require Gst` and
  # `Gst.parse_launch("pipewiresrc ! videoconvert ! pngenc ! filesink")` without
  # polluting the rest of the app's environment.
  cuPortalPython = final.writeShellScriptBin "python3" ''
    export GI_TYPELIB_PATH=${cuPortalTypelibs}''${GI_TYPELIB_PATH:+:$GI_TYPELIB_PATH}
    export GST_PLUGIN_SYSTEM_PATH_1_0=${cuPortalGstPlugins}''${GST_PLUGIN_SYSTEM_PATH_1_0:+:$GST_PLUGIN_SYSTEM_PATH_1_0}
    exec ${final.python3.withPackages (ps: [ ps.pygobject3 ])}/bin/python3 "$@"
  '';
in {
  claude-desktop = (final.callPackage
    "${claude-desktop-bin}/packaging/nix/package.nix"
    {
      claude-code = final.claude-code;
      # Drop gnome-screenshot so the cascade reaches the portal branch (see above).
      gnome-screenshot = null;
      # Portal+PipeWire screenshot deps. extraSessionPaths also re-introduces
      # claude-code onto PATH (package.nix only adds its dedicated claude-code
      # entry when extraSessionPaths == []), so keep claude-code in this list.
      extraSessionPaths = [
        final.claude-code
        cuPortalPython
        gst.gstreamer.bin     # gst-launch-1.0 (the _hasPortalDeps gate probes for it)
      ];
    }
  ).overrideAttrs (old: {
    # Their package.nix omits asar from nativeBuildInputs; the patch overlays
    # need it for the extract/repack each fragment performs.
    nativeBuildInputs = (old.nativeBuildInputs or [ ]) ++ [ final.asar ];
  });
})
