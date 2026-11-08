/*
  Measured boot feature that unlocks a LUKS image containing FIDO2 salt

  Flow:
   1. At build, embed initrd with `/var/lib/measured-boot/fido2-fde-salt.luks`
   2. At stage 1, TPM dm-crypt to `/dev/mapper/fido2-fde-salt`
   3. systemd strips and prepare salt to `/run/measured-boot/fido2-fde-salt`
*/

{ config, lib, ... }:
let
  pcrlockMounts = [
    "/var/lib/pcrlock.d"
    "/var/lib/systemd"
  ];
in
{
  # Managed systemd-pcrlock policy to unlock `/dev/mapper/fido2-fde-salt`
  boot.lanzaboote.measuredBoot = {
    enable = true;
    pcrs = [
      0 # platform-code (firmware version)
      4 # boot-loader-code (lanzaboote stub)
      7 # secure-boot-policy (PK, KEK, db, status)
    ];
  };

  boot.initrd = {
    # systemd-cryptsetup attaches the regular-file LUKS image through a loop
    # device. Include the module in stage 1 so that automatic setup can work.
    availableKernelModules = [ "loop" ];

    luks.devices."fido2-fde-salt" = {
      device = "/var/lib/measured-boot/fido2-fde-salt.luks";
      crypttabExtraOpts = [
        "headless=true"
        "noauto"
        "tpm2-device=auto"
      ];
    };

    systemd.services = {
      prepare-fido2-fde-salt = {
        description = "Acquire the TPM-bound FIDO2 salt";
        wantedBy = [ "systemd-cryptsetup@decrypted_root.service" ];
        wants = [ "systemd-cryptsetup@fido2\\x2dfde\\x2dsalt.service" ];
        after = [
          "systemd-cryptsetup@fido2\\x2dfde\\x2dsalt.service"
          "initrd-nixos-copy-secrets.service"
        ];
        before = [
          "systemd-cryptsetup@decrypted_root.service"
          "shutdown.target"
        ];
        conflicts = [ "shutdown.target" ];
        unitConfig.DefaultDependencies = "no";
        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
        };
        script = ''
          mkdir -p /run/measured-boot
          umask 0077
          if [ -e /dev/mapper/fido2-fde-salt ] \
            && dd if=/dev/mapper/fido2-fde-salt \
              of=/run/measured-boot/fido2-fde-salt \
              bs=32 count=1 status=none; then
            echo "Salt unlock success" > /dev/console
          else
            echo "Salt unlock fail" > /dev/console
            dd if=/dev/urandom of=/run/measured-boot/fido2-fde-salt \
              bs=32 count=1 status=none
          fi
          chmod 0400 /run/measured-boot/fido2-fde-salt
        '';
      };
    };
  };

  # The initrd cryptsetup unit is stopped automatically after systemd re-execs
  # on the real root. Remove the runtime copies once that handoff is complete.
  #
  # The upstream pcrlock units only order themselves after var.mount. Ensure
  # every writer sees the nested persistent mounts instead of the ephemeral root.
  #
  # The Varlink service (used by fwupd) otherwise builds a policy over
  # systemd's default PCR set, which differs from lanzaboote's make-policy.
  systemd.services = {
    cleanup-fido2-fde-salt = {
      description = "Remove the initrd FIDO2 salt runtime files";
      wantedBy = [ "basic.target" ];
      after = [ "systemd-cryptsetup@fido2\\x2dfde\\x2dsalt.service" ];
      before = [ "basic.target" ];
      unitConfig.DefaultDependencies = "no";
      serviceConfig.Type = "oneshot";
      script = ''
        rm -f /run/measured-boot/fido2-fde-salt
        if [ -e /dev/mapper/fido2-fde-salt ]; then
          systemd-cryptsetup detach fido2-fde-salt
        fi
      '';
    };
  }
  //
    lib.genAttrs
      [
        "systemd-pcrlock-firmware-code"
        "systemd-pcrlock-secureboot-policy"
        "systemd-pcrlock-secureboot-authority"
        "systemd-pcrlock-make-policy"
      ]
      (_: {
        unitConfig.RequiresMountsFor = pcrlockMounts;
      })
  // {
    "systemd-pcrlock@" = {
      unitConfig.RequiresMountsFor = pcrlockMounts;
      serviceConfig.ExecStart = [
        "" # unset previous value
        (lib.escapeShellArgs (
          [
            "${config.systemd.package}/lib/systemd/systemd-pcrlock"
            "--location=770"
          ]
          ++ map (pcr: "--pcr=${toString pcr}") config.boot.lanzaboote.measuredBoot.pcrs
        ))
      ];
    };
  };
}
