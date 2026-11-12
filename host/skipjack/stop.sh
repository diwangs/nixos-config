#!/bin/bash
# Cancel the long-lived `zed-dev` job started by skipjack-jump.
set -euo pipefail
export PATH="/opt/mprov/cloack/slurm/current/bin:$PATH"
scancel -u "$(id -un)" -n zed-dev "$@"
