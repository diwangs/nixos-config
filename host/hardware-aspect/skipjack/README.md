# Skipjack (JHU ARCH) dev environment

`homeConfigurations.ssangdi1` (`host/sentinel-skipjack-ssangdi1.hm.nix`) on
the Skipjack cluster, used from Zed on the laptop.

- **Nix:** the store lives at `/scratch/jhu/ycao43/ssangdi1/.nix` and is
  bind-mounted at `/nix` by `nix-user-chroot` (unprivileged user namespace).
- **Entry:** compute-node key logins hit a forced command in
  `~/.ssh/authorized_keys` (`~/.local/bin/skipjack-enter.sh`),
  which enters `/nix` and runs the requested command or a login zsh.
- **Job:** `ssh sentinel-skipjack` runs `skipjack-jump.sh` on the login
  node. It reuses or submits one `sentinel-skipjack` job (`interactive_cpu`, 4 hours,
  4 CPUs, 8G) and pipes ssh to that node. The job survives disconnects;
  `scancel -u "$USER" -n sentinel-skipjack` on the login node cancels it.
- `interactive_cpu` and `agentic` allow 4 CPUs and one job per user, at
  2000 MB per CPU, so larger `--mem` requests never start
  (`QOSMaxCpuPerUserLimit`).
- Activation installs these as real files, not store symlinks, because sshd
  and the login node read them outside `/nix`.

The laptop-side aliases `citadel-skipjack` (login node, shared MFA master) and
`sentinel-skipjack` (ProxyCommand through `skipjack-jump.sh`) live in the
os-secret `ssh-hosts` include, not in this repo.

`vscode_job.sh` is ARCH's original VS Code launcher, kept for reference.

## Bootstrap (once)

Run on a **compute node**, never on the login node. agenix is off on this host
(`age.enable = false`), so the switch never fetches the private `os-secret`
input and needs no agent forwarding. Going through `ssh sentinel-skipjack`
still needs your YubiKey key in `authorized_keys` before activation installs
the managed one.

1. On the login node (`ssh citadel-skipjack` from the laptop, MFA once), install the
   jump script and a temporary plain key:

   ```bash
   mkdir -p ~/.local/bin ~/.ssh && chmod 700 ~/.ssh
   # copy host/hardware-aspect/skipjack/skipjack-jump.sh here, e.g. with scp from the laptop
   chmod 755 ~/.local/bin/skipjack-jump.sh
   echo "<diwangsPiv from host/identity/ssh.nix>" >~/.ssh/authorized_keys
   chmod 600 ~/.ssh/authorized_keys
   ```

2. From the laptop, run `ssh sentinel-skipjack`. This submits `sentinel-skipjack` and gives
   you a plain shell on the node. Then:

   ```bash
   root=/scratch/jhu/ycao43/ssangdi1/.nix
   unshare --user true && echo userns-ok   # compute nodes must allow it
   mkdir -p "$root"
   curl -L -o ~/.local/bin/nix-user-chroot \
     https://github.com/nix-community/nix-user-chroot/releases/download/2.1.1/nix-user-chroot-bin-2.1.1-x86_64-unknown-linux-musl
   chmod 755 ~/.local/bin/nix-user-chroot

   # Lmod's default gcc module sets LD_LIBRARY_PATH, which breaks Nix binaries.
   env -u LD_LIBRARY_PATH ~/.local/bin/nix-user-chroot "$root" bash --noprofile --norc
   # now inside /nix (check: `echo $LD_LIBRARY_PATH` prints nothing):
   curl -L https://nixos.org/nix/install | sh -s -- --no-daemon --no-modify-profile
   . ~/.nix-profile/etc/profile.d/nix.sh
   git clone git@github.com:diwangs/nixos-config.git ~/.config/home-manager
   # home-manager calls nix itself, so enable flakes for the whole session
   export NIX_CONFIG="experimental-features = nix-command flakes"
   nix run home-manager -- switch -b bak --flake ~/.config/home-manager#ssangdi1
   ```

   Activation replaces `authorized_keys` with the forced-command version, so
   from the next login on, `ssh sentinel-skipjack` lands in `/nix` automatically.

After this, everything goes through `sentinel-skipjack`:

```bash
ssh sentinel-skipjack                     # login zsh inside /nix on the job's node
ssh sentinel-skipjack home-manager switch # update after pulling
ssh citadel-skipjack '/opt/mprov/cloack/slurm/current/bin/scancel -u "$USER" -n sentinel-skipjack'
```

In Zed, open `ssh://sentinel-skipjack/~/<project>`. The remote server comes from
the same `flake.lock` as the laptop's Zed, so the versions match.

To use different resources, pass sbatch flags to the jump script. They only
apply when a new job is submitted:
`ProxyCommand ssh citadel-skipjack '~/.local/bin/skipjack-jump.sh -p agentic -t 1-00:00:00'`.

## Caveats

- `/scratch` may be purged. If store paths vanish, run
  `nix-store --verify --check-contents --repair` and switch again.
- Keep to one job at a time: the Nix SQLite database is on WekaFS.
  Job reuse guarantees this.
- `authorized_keys` is fully managed, so add any other keys in the host
  module.
