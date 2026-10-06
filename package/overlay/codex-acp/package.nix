{
  lib,
  buildNpmPackage,
  fetchFromGitHub,
}:

buildNpmPackage rec {
  pname = "codex-acp";
  version = "2.1.1";

  src = fetchFromGitHub {
    owner = "agentclientprotocol";
    repo = "codex-acp";
    tag = "v${version}";
    hash = "sha256-bSxt9vtFnIrdZDmFJdYAfqkgm4BrGYKe420RamPkZvg=";
  };

  npmDepsHash = "sha256-7v7QE0cmYsd3JGu0VoT53yZ1rb9wYB+tXt05G1EEvz8=";

  meta = {
    description = "ACP adapter for the OpenAI Codex CLI";
    homepage = "https://github.com/agentclientprotocol/codex-acp";
    license = lib.licenses.asl20;
    mainProgram = "codex-acp";
  };
}
