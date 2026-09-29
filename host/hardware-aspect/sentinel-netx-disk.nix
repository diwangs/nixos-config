{
  config,
  lib,
  pkgs,
  ...
}:
let
  # Disko's --key-file path rejects a zero-byte passphrase. Start with a
  # disposable known passphrase, then replace it with a genuine empty keyslot
  # before the installed disk is considered ready to boot. The image builder
  # runs the same transition in extraPostVM.
  bootstrapPassword = pkgs.writeText "sentinel-netx-disposable-password" "sentinel-netx-bootstrap";
  # cryptsetup prints each prompt before tcsetattr(TCSAFLUSH). Give it time
  # to finish that input flush before sending an empty passphrase's Enter.
  enrollEmpty = pkgs.writeText "sentinel-netx-enroll-empty.exp" ''
    set timeout 120
    set disk [lindex $argv 0]
    set key [lindex $argv 1]
    spawn ${pkgs.cryptsetup}/bin/cryptsetup luksAddKey --key-file $key $disk
    expect {
      -re {Enter new passphrase[^:]*:} { after 200; send -- "\r" }
      timeout { exit 1 }
      eof { exit 1 }
    }
    expect {
      -re {Verify passphrase[^:]*:} { after 200; send -- "\r" }
      timeout { exit 1 }
      eof { exit 1 }
    }
    expect eof
    set result [wait]
    exit [lindex $result 3]
  '';
  verifyEmpty = pkgs.writeText "sentinel-netx-verify-empty.exp" ''
    set timeout 120
    set disk [lindex $argv 0]
    spawn ${pkgs.cryptsetup}/bin/cryptsetup open --test-passphrase $disk
    expect {
      -re {Enter passphrase[^:]*:} { after 200; send -- "\r" }
      timeout { exit 1 }
      eof { exit 1 }
    }
    expect eof
    set result [wait]
    exit [lindex $result 3]
  '';
  finalizeBootstrapKey = pkgs.writeShellScriptBin "sentinel-netx-finalize-bootstrap-key" ''
    set -euo pipefail
    if [ "$#" -ne 1 ] || [ ! -b "$1" ]; then
      echo "Usage: sentinel-netx-finalize-bootstrap-key ROOT_LUKS_PARTITION" >&2
      exit 2
    fi
    disk="$1"
    ${pkgs.cryptsetup}/bin/cryptsetup isLuks "$disk"
    ${pkgs.expect}/bin/expect -f ${enrollEmpty} -- "$disk" ${bootstrapPassword}
    ${pkgs.expect}/bin/expect -f ${verifyEmpty} -- "$disk"
    ${pkgs.cryptsetup}/bin/cryptsetup -q luksRemoveKey --key-file ${bootstrapPassword} "$disk"
    ${pkgs.expect}/bin/expect -f ${verifyEmpty} -- "$disk"
    if ${pkgs.cryptsetup}/bin/cryptsetup open --test-passphrase --key-file ${bootstrapPassword} "$disk"; then
      echo "Disposable LUKS passphrase still unlocks the disk" >&2
      exit 1
    fi
  '';
  btrfsOptions = [
    "compress=zstd"
    "noatime"
  ];
in
{
  # An authenticated root needs the cipher and integrity target before the
  # root filesystem is mounted. Keep the AES-NI implementation available when
  # the Proxmox CPU model exposes AES, with the generic implementation as a
  # fallback.
  boot.initrd.availableKernelModules = [
    "aegis128"
    "aegis128-aesni"
    "algif_aead"
    "dm-integrity"
  ];

  disko.imageBuilder.name = "sentinel-netx-disko";
  # Disko currently passes aggregateModules as vmTools.kernel, while this
  # nixpkgs pin expects a real kernel plus a separate kernelModules tree.
  # Keep the compatibility adjustment local to the image builder.
  disko.imageBuilder.pkgs = pkgs.extend (
    _final: prev: {
      vmTools = prev.vmTools // {
        override =
          args:
          prev.vmTools.override (
            (builtins.removeAttrs args [ "kernel" ])
            // {
              kernel = config.boot.kernelPackages.kernel;
              kernelModules = args.kernel;
            }
          );
      };
    }
  );
  disko.imageBuilder.extraDependencies = [
    pkgs.expect
    pkgs.cryptsetup
  ];
  # Also run this after a direct disko-install onto a VM-specific, full-size
  # disk. The image builder uses the same verified keyslot transition.
  system.build.sentinelNetxFinalizeBootstrapKey = finalizeBootstrapKey;
  disko.imageBuilder.extraPostVM = ''
    # This script is run with sudo by diskoImagesScript, not in a Nix build
    # sandbox. A failed keyslot operation must make the builder fail.
    set -euo pipefail
    (
      image="$out/sentinel-netx.raw"
      loopdev=$(${pkgs.util-linux}/bin/losetup --find --show --partscan "$image")
      trap '${pkgs.util-linux}/bin/losetup --detach "$loopdev"' EXIT
      rootpart="''${loopdev}p2"
      ${pkgs.systemdMinimal}/bin/udevadm settle --timeout=120
      test -b "$rootpart"
      ${finalizeBootstrapKey}/bin/sentinel-netx-finalize-bootstrap-key "$rootpart"
    )
  '';
  disko.devices.disk.main = {
    type = "disk";
    # This is the image-builder's device, not a runtime dependency. Runtime
    # mounts and LUKS unlock use stable partition labels.
    device = "/dev/vdb";
    imageName = "sentinel-netx";
    # Disposable bootstrap image only. The final authenticated LUKS volume is
    # formatted directly on a separate disk at its intended size.
    imageSize = "8G";
    content = {
      type = "gpt";
      partitions = {
        ESP = {
          size = "1G";
          type = "EF00";
          content = {
            type = "filesystem";
            format = "vfat";
            mountpoint = "/boot";
            mountOptions = [ "umask=0077" ];
          };
        };
        root = {
          size = "100%";
          content = {
            type = "luks";
            name = "sentinel-root";
            passwordFile = "${bootstrapPassword}";
            extraFormatArgs = [
              "--type"
              "luks2"
              "--cipher"
              "aegis128-random"
              "--key-size"
              "128"
              "--integrity"
              "aead"
            ];
            settings.tryEmptyPassphrase = true;
            content = {
              type = "btrfs";
              extraArgs = [
                "-L"
                "sentinel-root"
              ];
              subvolumes = {
                "/@root" = {
                  mountpoint = "/";
                  mountOptions = btrfsOptions;
                };
                "/@blank" = { };
                # State subvolumes can be snapshotted independently. @meta
                # holds machine-id and other small persistent state.
                "/states/@meta" = {
                  mountpoint = "/persist/states";
                  mountOptions = btrfsOptions;
                };
                "/states/@nixos" = {
                  mountpoint = "/persist/states/etc/nixos";
                  mountOptions = btrfsOptions;
                };
                "/states/@ssh" = {
                  mountpoint = "/persist/states/etc/ssh";
                  mountOptions = btrfsOptions;
                };
                "/states/@nixos-state" = {
                  mountpoint = "/persist/states/var/lib/nixos";
                  mountOptions = btrfsOptions;
                };
                "/states/@systemd" = {
                  mountpoint = "/persist/states/var/lib/systemd";
                  mountOptions = btrfsOptions;
                };
                "/states/@home" = {
                  mountpoint = "/persist/states/home/diwangs";
                  mountOptions = btrfsOptions;
                };
                # Cache subvolumes persist across reboot, but are not part of
                # state snapshots. /nix is mounted directly for early boot.
                "/caches/@meta" = {
                  mountpoint = "/persist/caches";
                  mountOptions = btrfsOptions;
                };
                "/caches/@nix" = {
                  mountpoint = "/nix";
                  mountOptions = btrfsOptions;
                };
                "/caches/@cloud" = {
                  mountpoint = "/persist/caches/var/lib/cloud";
                  mountOptions = btrfsOptions;
                };
                "/caches/@log" = {
                  mountpoint = "/persist/caches/var/log";
                  mountOptions = btrfsOptions;
                };
                "/caches/@varcache" = {
                  mountpoint = "/persist/caches/var/cache";
                  mountOptions = btrfsOptions;
                };
                "/caches/@homecache" = {
                  mountpoint = "/persist/caches/home/diwangs/.cache";
                  mountOptions = btrfsOptions;
                };
                "/caches/@pcrlock" = {
                  mountpoint = "/persist/caches/var/lib/pcrlock.d";
                  mountOptions = btrfsOptions;
                };
              };
            };
          };
        };
      };
    };
  };

  fileSystems =
    lib.genAttrs
      [
        "/nix"
        "/persist/states"
        "/persist/states/etc/nixos"
        "/persist/states/etc/ssh"
        "/persist/states/var/lib/nixos"
        "/persist/states/var/lib/systemd"
        "/persist/states/home/diwangs"
        "/persist/caches"
        "/persist/caches/var/lib/cloud"
        "/persist/caches/var/log"
        "/persist/caches/var/cache"
        "/persist/caches/home/diwangs/.cache"
        "/persist/caches/var/lib/pcrlock.d"
      ]
      (_: {
        neededForBoot = true;
      });

  # The installed @root is disposable; @blank is the never-written baseline.
  boot.initrd.systemd.services.reset-root = {
    description = "Restore the blank btrfs root subvolume";
    wantedBy = [ "cryptsetup.target" ];
    after = [ "cryptsetup.target" ];
    before = [ "sysroot.mount" ];
    unitConfig.DefaultDependencies = "no";
    serviceConfig.Type = "oneshot";
    script = ''
      mkdir -p /mnt
      mount -o subvolid=5 /dev/mapper/sentinel-root /mnt
      if btrfs subvolume show /mnt/@root >/dev/null 2>&1; then
        btrfs subvolume delete -Rc /mnt/@root
      fi
      btrfs subvolume snapshot /mnt/@blank /mnt/@root
      umount /mnt
    '';
  };
}
