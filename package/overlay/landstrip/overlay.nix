# Injects landstrip (the OS-level sandbox runner repackaged in ./package.nix) as
# `pkgs.landstrip`. Import it before any overlays that amend the package.
final: prev:
let
  upstreamLandstrip = final.callPackage ./package.nix { };
in
{
  landstrip = upstreamLandstrip.overrideAttrs (old: {
    # Downstream policy extension: permit every AF_INET/AF_INET6 socket while
    # retaining AF_UNIX pathname mediation. The patch header documents what it
    # touches and why it stays downstream.
    patches = (old.patches or [ ]) ++ [
      ./allow-all-inet-sockets.patch
      # Bug fix: brokered unix bind leaked `/proc/self/fd/N/...` into
      # getsockname(2), breaking go-plugin (Terraform providers).
      ./unix-bind-real-path.patch
      # Bug fix: filesystems without user xattrs (WekaFS on Skipjack) made the
      # optional per-executable policy lookup fail closed on every command.
      ./xattr-unsupported-no-policy.patch
    ];

    # `-F0` forbids fuzzy context matching, so a landstrip release that reworks
    # any of the patched regions fails loudly at patch time instead of quietly
    # landing a hunk somewhere it no longer belongs. This replaces the anchor
    # counting the previous Python-based `postPatch` did by hand.
    patchFlags = [
      "-p1"
      "-F0"
    ];
  });
}
