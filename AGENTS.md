# Secrets Handling
- To add secrets into the flake scope, run `git add -fN secret.toml`
- After running, always run `git reset --mixed` to remove secrets from the scope

# Building Instructions
- Run `sudo nixos-rebuild dry-build` to build