# Draft-specific plumbing shared by the patch fragments in THIS directory.
#
# WHY IT EXISTS: the draft packaging wraps the app in buildFHSEnv, and its
# `unwrapped` (which owns app.asar) is a `let` binding captured by store path in
# both `fhsEnv` and the top-level derivation. Overriding `passthru.unwrapped`
# would therefore never reach the launcher.
#
# Instead, `mkPatch` reaches INTO ../package.nix through callPackage's
# `.override`: it swaps the `stdenvNoCC` argument for one whose `mkDerivation`
# appends the fragment's `postFixup` to `unwrapped`. Upstream's own code then
# builds `fhsEnv`, the `.desktop` rewrite, the launcher, and passthru around
# the patched `unwrapped`, so nothing here mirrors (or drifts from) the PR.
#
# The ONE upstream detail this relies on: `unwrapped` is the only
# `stdenvNoCC.mkDerivation` call in ../package.nix that takes the
# `finalAttrs: { ... }` form (the top-level wrapper passes a plain attrset). The
# assert below fails evaluation if the snippet does not end up in
# `unwrapped`'s postFixup, instead of the patch silently landing nowhere.
#
# COMPOSITION: each fragment wraps whatever `stdenvNoCC` the previous one left
# in the override args, so fragments stack in any import order.
{ final, prev }:
{
  # mkAsarPatch: wrap a fragment's substituteInPlace body in its own
  # extract → patch → repack cycle, so fragments stay order-independent. `body`
  # mutates files under "$work/contents"; `label` is echoed into the build log so
  # a drifted anchor is traceable to its fragment. The repack is a plain
  # `asar pack`, exactly as ../package.nix's install does, and leaves the shipped
  # app.asar.unpacked dir untouched.
  mkAsarPatch =
    { label, body }:
    ''
      echo "[claude-desktop patch] ${label}"
      asarRoot=$out/lib/claude-desktop/resources
      work=$(mktemp -d)
      asar extract "$asarRoot/app.asar" "$work/contents"

      ${body}

      asar pack "$work/contents" "$work/app.asar"
      cp -f "$work/app.asar" "$asarRoot/app.asar"
      rm -rf "$work"
    '';

  # findChunk: main-process code is split into content-hashed
  # .vite/build/index.chunk-<hash>.js files whose names change every release, so
  # resolve at build time the file carrying a fixed-string anchor. Emits a bash
  # command substitution for the caller to assign.
  findChunk =
    locator:
    ''$(grep -rlF ${final.lib.escapeShellArg locator} "$work/contents/.vite/build")'';

  # mkPatch: turn a bash snippet that mutates the UNWRAPPED output tree into a
  # complete overlay attrset. `postFixup` runs after ../package.nix's install
  # (which already patches app.asar and writes the wrapper), typically wrapping a
  # `mkAsarPatch` body.
  mkPatch =
    { postFixup }:
    let
      claude-desktop = prev.claude-desktop.override (old: {
        stdenvNoCC = old.stdenvNoCC // {
          mkDerivation =
            args:
            old.stdenvNoCC.mkDerivation (
              if builtins.isFunction args then
                finalAttrs:
                let
                  attrs = args finalAttrs;
                in
                attrs
                // {
                  postFixup = (attrs.postFixup or "") + "\n" + postFixup;
                }
              else
                args
            );
        };
      });
    in
    {
      # Inside the attribute (not around the attrset) so the overlay's names
      # stay evaluable without forcing `final`.
      claude-desktop =
        assert final.lib.assertMsg
          (final.lib.hasInfix postFixup (claude-desktop.unwrapped.postFixup or ""))
          "claude-desktop-draft: mkPatch's postFixup did not reach `unwrapped`; re-check ../package.nix";
        claude-desktop;
    };
}
