#!/usr/bin/env bash
set -euo pipefail

usage() {
  printf 'Usage: %s /dev/disk/by-id/WHOLE_DISK\n' "$0" >&2
}

if [[ $# -ne 1 ]]; then
  usage
  exit 2
fi

final_disk=$1
if [[ $final_disk != /dev/disk/by-id/* || ! -b $final_disk ]]; then
  usage
  printf 'Choose an existing whole-disk /dev/disk/by-id/ path.\n' >&2
  exit 2
fi

resolved_disk=$(readlink -e -- "$final_disk")
if [[ $(lsblk -dn -o TYPE -- "$resolved_disk") != disk ]]; then
  printf 'Not a whole disk: %s -> %s\n' "$final_disk" "$resolved_disk" >&2
  exit 2
fi

check_blank_disk() {
  # The fresh-install path must not be used on a partitioned or mounted disk.
  if [[ $(lsblk -rn -o TYPE -- "$resolved_disk" | wc -l) -ne 1 ]] ||
    [[ -n $(lsblk -dn -o FSTYPE -- "$resolved_disk") ]] ||
    [[ -n $(lsblk -nr -o MOUNTPOINTS -- "$resolved_disk") ]]; then
    printf 'The disk is not blank or is mounted: %s\n' "$final_disk" >&2
    lsblk -o NAME,SIZE,TYPE,FSTYPE,MOUNTPOINTS -- "$resolved_disk" >&2
    exit 2
  fi
}

check_blank_disk

printf 'This will erase and format the entire disk:\n'
lsblk -o NAME,SIZE,TYPE,FSTYPE,MOUNTPOINTS -- "$resolved_disk"
printf 'By-id path: %s -> %s\n' "$final_disk" "$resolved_disk"
read -r -p 'Type the full by-id path to confirm: ' confirmation
if [[ $confirmation != "$final_disk" ]]; then
  printf 'Confirmation did not match; nothing was formatted.\n' >&2
  exit 1
fi

repo_root=$(cd -- "$(dirname -- "$0")/../.." && pwd -P)
disko_script=$(nix build --no-link --print-out-paths --impure \
  --argstr repoPath "$repo_root" --argstr finalDisk "$final_disk" --expr '
  { repoPath, finalDisk }:
  let
    flake = builtins.getFlake ("git+file://" + repoPath);
    installer = flake.nixosConfigurations.sentinel-netx5.extendModules {
      modules = [
        ({ lib, ... }: {
          disko.devices.disk.main.device = lib.mkForce finalDisk;
          disko.devices.disk.main.content.partitions.root.content.extraFormatArgs =
            lib.mkAfter [ "--progress-json" "--progress-frequency" "30" ];
        })
      ];
    };
  in installer.config.system.build.diskoScript')
if [[ ! -x $disko_script ]]; then
  printf 'Disko did not produce an executable script.\n' >&2
  exit 1
fi

# Recheck the symlink after the build, immediately before starting the job.
if [[ $(readlink -e -- "$final_disk") != "$resolved_disk" ]]; then
  printf 'The by-id path changed during the build; nothing was formatted.\n' >&2
  exit 1
fi
check_blank_disk

sudo systemd-run --unit=sentinel-disk-init --service-type=oneshot \
  --property=RemainAfterExit=yes "$disko_script"
printf 'Initialization started. Follow it with:\n'
printf '  sudo journalctl -fu sentinel-disk-init -o cat\n'
