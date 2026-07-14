# Sandbox
- Your Bash tool is sandboxed
- Your Read and Edit tools are not

# Verification
- If you add a new file, make sure git tracks them (e.g., intent to add) since Nix only reads git-tracked file.
- Verify your change with `nix flake check`