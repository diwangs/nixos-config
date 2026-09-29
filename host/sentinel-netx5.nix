# The same instance configuration installs unsigned, then switches to its
# os-secret-backed Secure Boot bundle when that input becomes available.
{
  agenix,
  lanzaboote,
  lib,
  os-secret,
  pkgs,
  ...
}:
let
  # The bundle is the phase marker. Do not reference its individual files
  # during the first installation, before the VM has generated its age key.
  hasSecureBootBundle =
    os-secret ? sentinel-netx5 && os-secret.sentinel-netx5 ? secure-boot;
  secureBoot = os-secret.sentinel-netx5.secure-boot;
  # systemd-creds -p prints a complete unit-file directive. NixOS's
  # serviceConfig option instead takes only the part after '='. Also accept
  # the value-only form used for paladin-iii's credential.
  ageIdentityCredential = lib.removePrefix "SetCredentialEncrypted=" (
    os-secret.systemd-creds.sentinel-netx5.ageIdentity
  );
  secretName = path: "sentinel-netx5/secure-boot/${path}";
  bootstrapBundle = "/run/sentinel-netx5-sbctl";
  encryptedBundle = "/run/agenix/sentinel-netx5/secure-boot";
in
{
  imports = [
    ./sentinel-netx.nix
    agenix.nixosModules.default
    lanzaboote.nixosModules.lanzaboote
  ];

  boot = {
    loader = {
      systemd-boot.enable = lib.mkForce false;
      efi.canTouchEfiVariables = lib.mkForce true;
    };
    lanzaboote = {
      enable = true;
      pkiBundle = if hasSecureBootBundle then encryptedBundle else bootstrapBundle;
      configurationLimit = 5;
      # Lanzaboote intentionally installs unsigned files only for generation
      # one. It must refuse unsigned files once os-secret is the key source.
      allowUnsigned = !hasSecureBootBundle;
      autoGenerateKeys.enable = !hasSecureBootBundle;
      autoEnrollKeys = {
        # Never enroll before the keys are safely encrypted in os-secret.
        enable = hasSecureBootBundle;
        autoReboot = false;
        includeMicrosoftKeys = false;
        # This is a disposable OVMF VM with its own EFI-vars disk, not a
        # physical machine. No Microsoft signatures are required.
        allowBrickingMyMachine = true;
      };
      measuredBoot = {
        # PCR 7 policy must be built after Secure Boot is actually enabled.
        enable = hasSecureBootBundle;
        pcrs = [
          0
          4
          7
        ];
        pcrlockDirectory = "/persist/caches/var/lib/pcrlock.d";
        pcrlockPolicy = "/persist/caches/var/lib/pcrlock.d/policy.json";
      };
    };
    initrd.luks.devices."sentinel-root" = {
      # After the bootstrap empty keyslot is removed, this attempt cannot
      # unlock the volume; TPM and recovery unlock remain available.
      tryEmptyPassphrase = lib.mkForce true;
      crypttabExtraOpts = lib.optionals hasSecureBootBundle [ "tpm2-device=auto" ];
    };
  };

  age.identityPaths = lib.optionals hasSecureBootBundle [
    "/run/credentials/agenix-install-secrets.service/age-identity"
  ];

  assertions = lib.optionals hasSecureBootBundle [
    {
      assertion = lib.hasPrefix "age-identity:" ageIdentityCredential;
      message = "sentinel-netx5's TPM credential must be named age-identity";
    }
  ];

  age.secrets = lib.optionalAttrs hasSecureBootBundle {
    ${secretName "GUID"}.file = secureBoot.GUID;
    ${secretName "keys/PK/PK.key"}.file = secureBoot.keys.PK."PK.key";
    ${secretName "keys/PK/PK.pem"}.file = secureBoot.keys.PK."PK.pem";
    ${secretName "keys/KEK/KEK.key"}.file = secureBoot.keys.KEK."KEK.key";
    ${secretName "keys/KEK/KEK.pem"}.file = secureBoot.keys.KEK."KEK.pem";
    ${secretName "keys/db/db.key"}.file = secureBoot.keys.db."db.key";
    ${secretName "keys/db/db.pem"}.file = secureBoot.keys.db."db.pem";
  };

  systemd.services = {
    # sbctl's default Landlock profile does not permit this custom /run
    # bundle path. The first-boot service is the only exception.
    generate-sb-keys = lib.mkIf (!hasSecureBootBundle) {
      serviceConfig.ExecStart = lib.mkForce "${pkgs.sbctl}/bin/sbctl --disable-landlock create-keys";
    };
  }
  // lib.optionalAttrs hasSecureBootBundle (
    (lib.genAttrs
      [
        "systemd-pcrlock-firmware-code"
        "systemd-pcrlock-secureboot-policy"
        "systemd-pcrlock-secureboot-authority"
        "systemd-pcrlock-make-policy"
      ]
      (_: {
        unitConfig.RequiresMountsFor = "/persist/caches/var/lib/pcrlock.d";
      })
    )
    // {
      agenix-install-secrets = {
        serviceConfig.SetCredentialEncrypted = ageIdentityCredential;
      };
      # Enrollment must not race agenix: the signed ESP and EFI variables
      # must use exactly the keys recovered from the encrypted bundle.
      prepare-sb-auto-enroll = {
        requires = [ "agenix-install-secrets.service" ];
        after = [ "agenix-install-secrets.service" ];
        # nixos-rebuild test can start newly wanted units. Keep enrollment
        # inert until the operator has compared every recovered key with
        # the first-boot bundle and installed a signed boot generation.
        unitConfig.ConditionPathExists = [
          "/run/sentinel-netx5-ready-for-enroll"
        ];
      };
    }
  );
}
