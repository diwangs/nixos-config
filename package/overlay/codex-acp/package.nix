{
  lib,
  buildNpmPackage,
  fetchFromGitHub,
}:

buildNpmPackage rec {
  pname = "codex-acp";
  version = "1.13.1";

  src = fetchFromGitHub {
    owner = "agentclientprotocol";
    repo = "codex-acp";
    tag = "v${version}";
    hash = "sha256-lVsj8RqE8XwCblOBSk3B4Nckx4h1o1BHMRrmpkhrIEw=";
  };

  npmDepsHash = "sha256-jXXvfg2bPZlvkNBZUw3ptpoOy9wOcvl2B8J0HnpX79c=";

  meta = {
    description = "ACP adapter for the OpenAI Codex CLI";
    homepage = "https://github.com/agentclientprotocol/codex-acp";
    license = lib.licenses.asl20;
    mainProgram = "codex-acp";
  };
}
