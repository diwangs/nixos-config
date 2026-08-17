{
  lib,
  buildNpmPackage,
  fetchFromGitHub,
}:

buildNpmPackage rec {
  pname = "codex-acp";
  version = "1.4.0";

  src = fetchFromGitHub {
    owner = "agentclientprotocol";
    repo = "codex-acp";
    tag = "v${version}";
    hash = "sha256-9oUtDBE1HINQaJhk4Le5GWN3YODNwDpRaVZlnDV9a5c=";
  };

  npmDepsHash = "sha256-tHnOMBXerUKBqTQM+jbXT3F9wgodvP6xdWJd7XNwhxE=";

  meta = {
    description = "ACP adapter for the OpenAI Codex CLI";
    homepage = "https://github.com/agentclientprotocol/codex-acp";
    license = lib.licenses.asl20;
    mainProgram = "codex-acp";
  };
}
