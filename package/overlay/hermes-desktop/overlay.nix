{ hermes-agent }:
final: _prev: {
  hermes-desktop = final.callPackage ./package.nix { inherit hermes-agent; };
}
