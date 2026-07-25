# Sandbox
- You are running inside a sandbox that restricts directories and AF_UNIX sockets you could access (inlcuding from Bash).
- The sandbox does not restrict network access.
- `--unpack` prefetch doesn't work since `O_PATH` is denied by the sandbox (e.g., `nix-prefetch-url --unpack`, `nix store prefetch-file --unpack`); use a streaming fetch instead (`nix flake prefetch`, `builtins.fetchTarball`, or an fixed-output derivation in `nix build`).

# Verification
- If you add a new file, make sure git tracks them (e.g., intent to add) since Nix only reads git-tracked file.
- Verify your change with `nix flake check` and format them with `nix fmt`.
