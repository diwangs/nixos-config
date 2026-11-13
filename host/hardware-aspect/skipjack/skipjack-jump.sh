#!/bin/bash
# ProxyCommand target on the Skipjack login node, installed as a real file by
# host/sentinel-skipjack-ssangdi1.hm.nix. Reuses (or submits) one long-lived
# job named `sentinel-skipjack`, then pipes stdio to that node's sshd.
# Disconnecting leaves the job running; cancel it with
# `scancel -u "$USER" -n sentinel-skipjack`.
#
# Extra arguments go to sbatch when a new job is submitted, e.g.
#   ProxyCommand ssh citadel-skipjack '~/.local/bin/skipjack-jump.sh -p agentic -t 1-00:00:00'
# Only Slurm queries run here: nothing heavy on the login node.
set -euo pipefail

export PATH="/opt/mprov/cloack/slurm/current/bin:$PATH"
name=sentinel-skipjack

find_job() {
  squeue -h -u "$(id -un)" -n "$name" -t PENDING,CONFIGURING,RUNNING -o %i |
    head -1
}

# Serialize lookup + submit so parallel connections share one job.
lock_dir="${XDG_RUNTIME_DIR:-/tmp}"
exec 9>"$lock_dir/skipjack-jump.lock"
flock 9
jobid="$(find_job)"
if [ -z "$jobid" ]; then
  account="$(sacctmgr -n -P show user "$(id -un)" format=DefaultAccount 2>/dev/null | head -1)"
  jobid="$(sbatch --parsable \
    --job-name="$name" \
    ${account:+--account="$account"} \
    --comment=accept_cost \
    --partition=interactive_cpu \
    --time=04:00:00 \
    --cpus-per-task=4 \
    --mem-per-cpu=2000M \
    --output=/dev/null \
    "$@" \
    --wrap='exec sleep infinity')"
  jobid="${jobid%%;*}"
  echo "skipjack-jump.sh: submitted job $jobid" >&2
fi
flock -u 9
exec 9>&-

state=""
for _ in $(seq 1 900); do
  state="$(squeue -h -j "$jobid" -o %T 2>/dev/null || true)"
  case "$state" in
    RUNNING) break ;;
    "")
      echo "skipjack-jump.sh: job $jobid is gone" >&2
      exit 1
      ;;
  esac
  sleep 2
done
if [ "$state" != RUNNING ]; then
  echo "skipjack-jump.sh: job $jobid still $state, giving up" >&2
  exit 1
fi

node="$(scontrol show hostnames "$(squeue -h -j "$jobid" -o %N)" | head -1)"
echo "skipjack-jump.sh: job $jobid on $node" >&2

# Skipjack has no netcat; use bash's /dev/tcp. sshd may lag the job start.
for _ in $(seq 1 30); do
  if (: <>"/dev/tcp/$node/22") 2>/dev/null; then break; fi
  sleep 1
done
exec 3<>"/dev/tcp/$node/22"
cat <&3 &
up=$!
cat >&3
kill "$up" 2>/dev/null || true
