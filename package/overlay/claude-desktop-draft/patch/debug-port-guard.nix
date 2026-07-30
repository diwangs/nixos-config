# Debug-enablement overlay for the draft (buildFHSEnv) packaging. Opens BOTH
# debugging surfaces, which are gated by two SEPARATE mechanisms:
#   - Renderer / browser CDP (--remote-debugging-port): a JS guard in
#     index.pre.js exits the app; we drop `&&process.exit(1)` (same substitution
#     as ../../claude-desktop/patch/debug-port-guard.nix).
#   - Main-process inspector (--inspect / SIGUSR1 → 9229): gated by the Electron
#     `EnableNodeCliInspectArguments` build fuse, shipped OFF. With it off,
#     SIGUSR1 has no handler and its default disposition TERMINATES the app. We
#     flip that fuse ON in the binary (see step 2 below).
# Both are DEBUG-ONLY; the fuse flip re-enables Node inspection of the
# privileged main process, so do not import this in a shipping config.
#
# It has to be wired in differently from the base overlay: the draft's app.asar
# lives in `passthru.unwrapped`, so the patch targets that and the FHS wrapper is
# rebuilt around it. That plumbing lives in ./lib.nix's `mkPatch`.
#
# For CDP work you usually don't even want the FHS chroot in the way: the
# guard-free binary is exposed at `claude-desktop.unwrapped` (non-FHS), so
# `nix run .#...claude-desktop.unwrapped -- --remote-debugging-port=9222`
# gives the cleanest dynamic-analysis surface.
#
# Import AFTER ../overlay.nix in ../../../../nixos.nix.
final: prev:
let
  helpers = import ../../claude-desktop/patch/lib.nix { inherit (final) lib; };
  draft = import ./lib.nix { inherit final prev; };
in
draft.mkPatch {
  postFixup =
    # 1. Drop the renderer-CDP exit guard in app.asar.
    helpers.mkAsarPatch {
      label = "debug-port guard";
      body = ''
        substituteInPlace "$work/contents/.vite/build/index.pre.js" \
          --replace-warn \
            '&&process.exit(1)' \
            '&&void 0'
      '';
    }
    + "\n"
    # 2. Flip the Electron `EnableNodeCliInspectArguments` fuse ON so the main
    # process honors --inspect / --inspect-brk and the SIGUSR1 inspector
    # handler. Anthropic ships it OFF (verified byte-identical in 1.17377.1
    # and 1.24012.9), which is why bare SIGUSR1 TERMINATES the app instead of
    # opening port 9229. DEBUG-ONLY: this re-enables Node inspection of the
    # privileged main process — do not ship it enabled.
    #
    # Runs in postFixup, after autoPatchelfHook's ELF rewrite, so the sentinel
    # offset is final. The fuse block is not part of app.asar, so this is
    # independent of the (enabled) EnableEmbeddedAsarIntegrityValidation fuse.
    + ''
      fuseBin=$out/lib/claude-desktop/claude-desktop
      fuseSentinel='dL7pKGdnNz796PbbjQWNKmHXBZaB9tsX'
      fuseOff=$(grep -aboe "$fuseSentinel" "$fuseBin" | head -1 | cut -d: -f1)
      if [ -z "$fuseOff" ]; then
        echo "flip-inspect-fuse: fuse sentinel not found in $fuseBin" >&2
        exit 1
      fi
      # wire layout: [sentinel(32B)][schema-version][fuse-count][fuses...];
      # EnableNodeCliInspectArguments is fuse index 3.
      fusePos=$((fuseOff + 32 + 2 + 3))
      fuseCur=$(dd if="$fuseBin" bs=1 skip="$fusePos" count=1 2>/dev/null | od -An -tu1 | tr -d ' ')
      case "$fuseCur" in
        48) # 0x30 '0' = disabled -> flip to 0x31 '1'
            printf '\x31' | dd of="$fuseBin" bs=1 seek="$fusePos" count=1 conv=notrunc 2>/dev/null
            echo "flip-inspect-fuse: EnableNodeCliInspectArguments ON (byte $fusePos)" ;;
        49) echo "flip-inspect-fuse: already ON, nothing to do" ;;
        *)  echo "flip-inspect-fuse: unexpected fuse byte '$fuseCur' at $fusePos; aborting" >&2
            exit 1 ;;
      esac
    '';
}
