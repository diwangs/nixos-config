{
  lib,
  buildNpmPackage,
  fetchFromGitHub,
}:

buildNpmPackage rec {
  pname = "codex-acp";
  version = "1.1.14";

  src = fetchFromGitHub {
    owner = "agentclientprotocol";
    repo = "codex-acp";
    tag = "v${version}";
    hash = "sha256-Mz4kxOvJPDp7R2H2wwTkPuuAICUJXxHdyFvtphOfD/M=";
  };

  npmDepsHash = "sha256-oST6ENGfWoa65Ts3RrmHUm5G+OgTQ/StptbnQzlJN/E=";

  meta = {
    description = "ACP adapter for the OpenAI Codex CLI";
    homepage = "https://github.com/agentclientprotocol/codex-acp";
    license = lib.licenses.asl20;
    mainProgram = "codex-acp";
  };
}
