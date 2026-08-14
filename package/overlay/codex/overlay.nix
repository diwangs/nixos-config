# Temporary Codex prerelease pin for the full-filesystem Bubblewrap `/dev` fix:
# https://github.com/openai/codex/pull/37349
#
# Remove this overlay once Codex 0.148.0 or newer reaches nixpkgs.
final: prev:
let
  version = "0.148.0-alpha.12";
  src = final.fetchFromGitHub {
    owner = "openai";
    repo = "codex";
    tag = "rust-v${version}";
    hash = "sha256-IDvprpQQLhZzpIpTs0BBpSm7HtFbmOqTh4FVS5gwVyA=";
  };
  librustyV8 = final.fetchurl {
    url = "https://github.com/denoland/rusty_v8/releases/download/v150.4.0/librusty_v8_release_x86_64-unknown-linux-gnu.a.gz";
    hash = "sha256-WGn9twcbHyHyAKl86X0gElh34PMc2ALtmd4sU/SIsGw=";
  };
  librustyV8SrcBinding = final.fetchurl {
    url = "https://github.com/denoland/rusty_v8/releases/download/v150.4.0/src_binding_release_x86_64-unknown-linux-gnu.rs";
    hash = "sha256-dyeCauR5vbZF6Acjn7EtH44uI956bPFvXuWSaQ0dhQY=";
  };
in
{
  codex = prev.codex.overrideAttrs (old: {
    inherit version src;

    cargoDeps = final.rustPlatform.fetchCargoVendor {
      inherit (old) pname;
      inherit version src;
      sourceRoot = "${src.name}/codex-rs";
      hash = "sha256-PpAGxlgxGMHPg3ye9brlKghkB6Fuj8V1RG/s8C7dlNg=";
    };

    env = old.env // {
      RUSTY_V8_ARCHIVE = librustyV8;
      RUSTY_V8_SRC_BINDING_PATH = librustyV8SrcBinding;
    };
  });
}
