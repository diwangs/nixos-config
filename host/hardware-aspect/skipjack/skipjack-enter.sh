#!/bin/bash
# Forced command for compute-node SSH, installed as a real file (not a store
# symlink) by host/sentinel-skipjack-ssangdi1.hm.nix. sshd runs it outside
# /nix, so it re-executes itself inside nix-user-chroot, then runs the
# requested command (Zed, scp, ssh-ng, ...) or a login shell.
#
# Also usable by hand, e.g. `skipjack-enter.sh` in an `srun --pty` shell.
set -euo pipefail

nix_root=@nixRoot@
chroot_bin=@chrootBin@

# Outside the chroot: Skipjack has no /nix, so its presence means we're in.
# (Not /nix/store: a freshly cleared store has /nix but no store yet.)
if [ ! -d /nix ]; then
  if [ -x "$chroot_bin" ] && [ -d "$nix_root/store" ]; then
    exec "$chroot_bin" "$nix_root" "$0" "$@"
  fi
  # Never lock the key out of the node: degrade to the host environment.
  echo "skipjack-enter.sh: $nix_root not usable, continuing without Nix" >&2
  cmd="${SSH_ORIGINAL_COMMAND:-}"
  if [ -n "$cmd" ]; then exec /bin/bash -c "$cmd"; fi
  if [ $# -gt 0 ]; then exec "$@"; fi
  exec -l /bin/bash
fi

# Inside the chroot. Lmod's default modules (gcc/12.3.0) export
# LD_LIBRARY_PATH, which makes Nix binaries load the cluster's older libstdc++.
# Keep it aside for host tools (e.g. after `module load`).
if [ -n "${LD_LIBRARY_PATH:-}" ]; then
  export SKIPJACK_HOST_LD_LIBRARY_PATH="$LD_LIBRARY_PATH"
  unset LD_LIBRARY_PATH
fi

# Load the Home Manager session environment.
set +u
for profile in "$HOME/.nix-profile" "$HOME/.local/state/nix/profile"; do
  if [ -d "$profile/bin" ]; then
    PATH="$profile/bin:$PATH"
    [ -r "$profile/etc/profile.d/nix.sh" ] && . "$profile/etc/profile.d/nix.sh"
    [ -r "$profile/etc/profile.d/hm-session-vars.sh" ] &&
      . "$profile/etc/profile.d/hm-session-vars.sh"
  fi
done
set -u
export PATH

shell="$(command -v zsh || echo /bin/bash)"
export SHELL="$shell"

cmd="${SSH_ORIGINAL_COMMAND:-}"
case "$cmd" in
  "")
    if [ $# -gt 0 ]; then exec "$@"; fi
    exec -l "$shell"
    ;;
  internal-sftp*) exec /usr/libexec/openssh/sftp-server ;;
  *) exec "$shell" -c "$cmd" ;;
esac
