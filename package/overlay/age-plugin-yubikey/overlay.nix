# `age-plugin-yubikey` PR #221 to support YubiKey 5.7 AES management key
# Technically this also adds X25519, but is not upstreamed as a tagged
# recipient yet, so we just ignore it and wait.
final: prev:
let
  rev = "bf883aef9b043d04097ef1d1cf23b57efaee4ec4";
  version = "0.5.1-unstable-2026-04-22";
  # Both git crates resolve to the same rage tree, so they share one hash.
  rageSrcHash = "sha256-8ofjDAXt5+LY+okaclSbZuS/nncqFl3pEYgVvN3syCY=";
in
{
  age-plugin-yubikey = prev.age-plugin-yubikey.overrideAttrs (old: {
    inherit version;

    src = prev.fetchFromGitHub {
      owner = "dlubawy";
      repo = "age-plugin-yubikey";
      inherit rev;
      hash = "sha256-FonvnzVwF/J3tAIXOOzs+w7PLyPK7GMWd7+MPQR4PN4=";
    };

    cargoDeps = final.rustPlatform.importCargoLock {
      lockFile = ./Cargo.lock;
      outputHashes = {
        "age-core-0.11.0" = rageSrcHash;
        "age-plugin-0.6.1" = rageSrcHash;
      };
    };

    meta = old.meta // {
      changelog = "https://github.com/str4d/age-plugin-yubikey/pull/221";
    };
  });
}
