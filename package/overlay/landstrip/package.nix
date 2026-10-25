/*
  landstrip: OS-level sandbox runner for coding agents.

  On Linux it enforces the sandbox with Landlock LSM (kernel-native path access,
  no bind-mounts, no user namespaces, no /proc remount) plus a seccomp broker for
  what Landlock can't express statically (glob deny-write, unix-socket allowlist).
  This is a drop-in replacement for the bubblewrap-based Claude Code Bash sandbox,
  sidestepping the whole class of bwrap bind-mount/namespace bugs the previous
  `claude-code.nix` overlay worked around.

  Rust (edition 2024, rust >= 1.85). The `landlock` and `seccompiler` crates carry
  no C dependency, but since 0.19.19 the `openssl` crate is pulled in with its
  `vendored` feature; OPENSSL_NO_VENDOR links nixpkgs' OpenSSL instead of
  building one from source (which also needs perl).

  Also consumed by the Claude Code Bash-tool wrapper in
  ../../home-manager.headless.nix (CLAUDE_CODE_SHELL -> landstrip -p <policy> -- bash).
  OpenCode fetches its own copy through the opencode-landstrip npm plugin, so this
  package only serves Claude Code.
*/

{
  lib,
  rustPlatform,
  fetchFromGitHub,
  pkg-config,
  openssl,
}:

let
  version = "0.20.11";
in
rustPlatform.buildRustPackage {
  pname = "landstrip";
  inherit version;

  src = fetchFromGitHub {
    owner = "landstrip";
    repo = "landstrip";
    tag = version;
    hash = "sha256-eTCxXU7TbIHkGLyuiowsYB3SO0vrSpzxw6N+kdi/E3k=";
  };

  cargoRoot = "packages/landstrip";
  buildAndTestSubdir = "packages/landstrip";
  cargoHash = "sha256-TkKi5oEOaVBo6F1KYWa/mNMS1qE1dNY1jXf8qZ1dDlY=";

  nativeBuildInputs = [ pkg-config ];
  buildInputs = [ openssl ];
  env.OPENSSL_NO_VENDOR = 1;

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
