{
  lib,
  buildNpmPackage,
  fetchFromGitHub,
}:

buildNpmPackage rec {
  pname = "codex-acp";
  version = "2.2.2";

  src = fetchFromGitHub {
    owner = "agentclientprotocol";
    repo = "codex-acp";
    tag = "v${version}";
    hash = "sha256-9qIKaDZJ80PVO7/qBfbOE7un2Ukk92bZVrIaHG/K8P8=";
  };

  npmDepsHash = "sha256-4wXnQnPEUp0DtNphXBS5/WQkgErRD631xOB0KqDXf4U=";

  meta = {
    description = "ACP adapter for the OpenAI Codex CLI";
    homepage = "https://github.com/agentclientprotocol/codex-acp";
    license = lib.licenses.asl20;
    mainProgram = "codex-acp";
  };
}
