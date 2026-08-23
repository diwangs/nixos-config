{
  lib,
  buildNpmPackage,
  fetchFromGitHub,
}:

buildNpmPackage rec {
  pname = "codex-acp";
  version = "1.6.2";

  src = fetchFromGitHub {
    owner = "agentclientprotocol";
    repo = "codex-acp";
    tag = "v${version}";
    hash = "sha256-QNQ9x4CEO6xzKDd1vggBbntnGLjI1TBmg5ydCWM3T7k=";
  };

  npmDepsHash = "sha256-uK03isdvl9tpYDF1sapHjmPdhtLGbdjE3cDU/qFa5G0=";

  meta = {
    description = "ACP adapter for the OpenAI Codex CLI";
    homepage = "https://github.com/agentclientprotocol/codex-acp";
    license = lib.licenses.asl20;
    mainProgram = "codex-acp";
  };
}
