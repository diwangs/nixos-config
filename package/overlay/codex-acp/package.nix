{
  lib,
  buildNpmPackage,
  fetchFromGitHub,
}:

buildNpmPackage rec {
  pname = "codex-acp";
  version = "1.1.9";

  src = fetchFromGitHub {
    owner = "agentclientprotocol";
    repo = "codex-acp";
    tag = "v${version}";
    hash = "sha256-c8Sgj9XNDAO25UOa+vEy619mSi3tG3NJHbKnV1QzOo8=";
  };

  npmDepsHash = "sha256-MsP8g4X4yX/K8nwNieQdgGaJfAf8FOc0D3OCypTx+w0=";

  meta = {
    description = "ACP adapter for the OpenAI Codex CLI";
    homepage = "https://github.com/agentclientprotocol/codex-acp";
    license = lib.licenses.asl20;
    mainProgram = "codex-acp";
  };
}
