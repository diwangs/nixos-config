/*
  landstrip: OS-level sandbox runner for coding agents.

  On Linux it enforces the sandbox with Landlock LSM (kernel-native path access,
  no bind-mounts, no user namespaces, no /proc remount) plus a seccomp broker for
  what Landlock can't express statically (glob deny-write, unix-socket allowlist).
  This is a drop-in replacement for the bubblewrap-based Claude Code Bash sandbox,
  sidestepping the whole class of bwrap bind-mount/namespace bugs the previous
  `claude-code.nix` overlay worked around.

  Pure-Rust (edition 2024, rust >= 1.85; `landlock` and `seccompiler` crates carry
  no C dependency), so this needs no pkg-config/libseccomp buildInputs.

  Also consumed by the Claude Code Bash-tool wrapper in
  ../../home-manager.devbox.nix (CLAUDE_CODE_SHELL -> landstrip -p <policy> -- bash).
  OpenCode fetches its own copy through the opencode-landstrip npm plugin, so this
  package only serves Claude Code.
*/

{
  lib,
  rustPlatform,
  fetchFromGitHub,
}:

let
  version = "0.18.42";
in
rustPlatform.buildRustPackage {
  pname = "landstrip";
  inherit version;

  src = fetchFromGitHub {
    owner = "landstrip";
    repo = "landstrip";
    tag = version;
    hash = "sha256-vpmL722dxiXaL8/E2qv1Fv9FaQ0Hii0bEOy9C9BHy58=";
  };

  cargoRoot = "packages/landstrip";
  buildAndTestSubdir = "packages/landstrip";
  cargoHash = "sha256-/i7c7dPWE/btBwTkbd8f2YipqjBWGACb37Z+Pw5Mkhg=";

  # The test suite exercises live Landlock/seccomp enforcement and needs a
  # real kernel, which the Nix build sandbox does not provide.
  doCheck = false;

  meta = {
    description = "OS-level sandbox runner for coding agents (Landlock + seccomp)";
    homepage = "https://github.com/landstrip/landstrip";
    license = lib.licenses.lgpl21Plus;
    mainProgram = "landstrip";
    platforms = lib.platforms.linux;
  };
}
