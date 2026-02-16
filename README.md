# diwangs' NixOS Configuration
This repo contains the NixOS configuration that I use in my laptop. This GitHub
repo mainly serves as a backup storage, but also to showcase the cool stuff 
that I manage to do in my laptop with Nix.

## Philosophy
- Hardened
    - Full-disk encryption
    - Hardened kernel with CFI (Clang-compiled)
    - Encrypted DNS-on-Tor
    - YubiKey-based authentication
    - TODO:
        - Verified boot
        - luksSuspend-on-root
- Impermanence: opt-in and explicit state
    - In order to boot, NixOS only needs 
        - `/boot` (ESP, contains kernel and initrd)
        - `/nix` (files that will be linked by initrd (NixOS Stage 1))
    - Does not use the Impermanence module (yet?)
- Bleeding-edge (on most things)
    - Wayland only (when possible)
    - Pipewire
    - Support for IPv6-only network
- Aspect-based separation: divides code into cross-cutting concerns
    - Inspired by Aspect-oriented Programming (AOP), improves reasoning about the code
    - The main criticism of AOP was about unclear control-flow, but since Nix is a declarative language, this is a non-issue (and is supported by structures such as `kernelPatches`)
    - The other criticism of AOP was about the unclear definition of what an "aspect" even is, since cross-cutting concerns potentially cross-cut each other. To resolve this, we make sure that the aspect defined in the file is not overly broad and suits the variables that Nix provides.
        - Good example -> `power` (mainly `tlp`), `key-management` (mainly `pgp`), `locale`
        - Bad example -> `security`, `performance`

## Structure
- `flake.nix` and `flake.lock` - root configuration
- `hardware` - Hardware-specific configuration, does not support rollback
    - That is probably not useful to copy, but could be studied
- `system` - How the OS (and 'system-layer') is managed
    - `aspect` - Configurations of the various aspects of the system
- `package` - Define packages to install
- Secrets are separated in a `secret.toml` file (not commited)

### Hardware
These are Nix files that is not-portable across machines.
Changes on underlying hardware are not rollback-able (e.g., partitions)
Specifically, this is for:
- Framework 13 - 7040 edition
- Disk: Btrfs on AEAD LUKS, with impermanence scheme
- YubiKey

### Aspect
- Unless specified, aspects belong to `nixos` instead of `home-manager`
- Aspects belonging to `home-manager` are stored in a module with `.hm.nix` suffix

#### Network
- IPv6-only network
- Encrypted DNS-on-Tor

#### Key Management
PGP, SSH, Git signing, age
- Use a PGP
- Use `gpg-agent` for SSH

### Package
Packages are split into 3 categories

- __NixOS packages__ - packages that are used by root (e.g., systemd, flake, etc.)
    - e.g. `git`, `fw-ectool`
- __Home Manager packages__ - packages that are not used by root and doesn't provide syncing, managed by home-manager
    - e.g. `vscode`, `vlc`
    - Usually rely on dotfiles
    - We sync with snapshoting and support rollback
- __Flatpak packages__ - packages that are not used by root and does provide syncing, managed by flatpak
    - e.g. Spotify, Steam
    - Doesn't really need snapshoting and rollback, since account data is backed up
    - Most are proprietary (or web apps), in which we eliminate (or greatly reduce the need for) unfree packages in NixOS itself, making it more functionally pure.
    - Some packages are official! (e.g. Discord, Brave, Obsidian). This make sure we get the latest update faster.
