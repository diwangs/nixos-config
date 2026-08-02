# Injects codex-acp (ACP adapter for the OpenAI Codex CLI, packaged in
# ./package.nix) as `pkgs.codex-acp`. Import it in ../../../nixos.nix and
# ../../../flake.nix's `nixpkgs.overlays`. Consumed by the "codex-acp" Zed
# agent_servers entry in ../../home-manager.devbox.nix.
final: prev: {
  codex-acp = final.callPackage ./package.nix { };
}
