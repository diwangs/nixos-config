# Carry Codex 0.158.0 until the pinned nixpkgs input reaches it.
final: prev: {
  codex = prev.codex.overrideAttrs (finalAttrs: {
    version = "0.158.0";
    src = final.fetchFromGitHub {
      owner = "openai";
      repo = "codex";
      tag = "rust-v0.158.0";
      hash = "sha256-6ogqs75pG4+hxG6RqwBwJPWd3wGks2wBID/epha9+Ds=";
    };
    cargoHash = "sha256-D8+caV6Q9H2JnZNhazV1kqgV0dePh3qQyXnRMgeSYak=";
    # buildRustPackage materializes cargoDeps before overrideAttrs runs, so
    # changing cargoHash alone would retain the 0.157 vendor derivation.
    cargoDeps = final.rustPlatform.fetchCargoVendor {
      inherit (finalAttrs) src sourceRoot;
      pname = "codex";
      version = "0.158.0";
      hash = "sha256-D8+caV6Q9H2JnZNhazV1kqgV0dePh3qQyXnRMgeSYak=";
    };
  });
}
