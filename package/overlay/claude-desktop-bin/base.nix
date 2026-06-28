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
{ self }:
(final: prev: {
  claude-desktop = (final.callPackage
    "${self.inputs.claude-desktop}/packaging/nix/package.nix"
    { claude-code = final.claude-code; }
  ).overrideAttrs (old: {
    # Their package.nix omits asar from nativeBuildInputs; the patch overlays
    # need it for the extract/repack each fragment performs.
    nativeBuildInputs = (old.nativeBuildInputs or [ ]) ++ [ final.asar ];
  });
})
