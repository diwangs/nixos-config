# For Framework 13 (for Chromebook and 7040 boards)
{
  lib,
  pkgs,
  os-secret,
  lanzaboote,
  impermanence,
  nixos-hardware,
  ...
}:
{
  imports = [
    # Laptop hardware
    # Semi-portable configs
    lanzaboote.nixosModules.lanzaboote
    impermanence.nixosModules.impermanence
    nixos-hardware.nixosModules.framework-13-7040-amd

    ./hardware-aspect/mainboard-7040.nix
    ./hardware-aspect/disk.nix
    ./hardware-aspect/measured-boot.nix
    ./hardware-aspect/kensington-infinity-dock.nix
    ./hardware-aspect/thunderbolt-initrd.nix
    ./hardware-aspect/printer.nix
  ];

  hardware = {
    # Enable non-free firmware (Qualcomm NCM865, Radeon, NPU, etc.)
    # This is defined in `not-detected.nix`, but let's define explicitly
    enableRedistributableFirmware = lib.mkDefault true;
    sensor.iio.enable = true; # auto-brightness

    # Peripherals
    hackrf.enable = true;
    wooting.enable = true; # unfree
  };

  # Lanzaboote replaces the systemd-boot module and signs the boot chain.
  boot = {
    loader = {
      timeout = 0; # Could still select by tapping arrow keys
      efi.canTouchEfiVariables = true;
      systemd-boot.enable = lib.mkForce false; # Use through lanzaboote instead
    };
    lanzaboote = {
      enable = true;
      pkiBundle = "/run/agenix/paladin-iii/secure-boot";
      configurationLimit = 4; # Limit is 4 since lanzaboote 1.2.0.
      autoGenerateKeys.enable = false; # Use through agenix instead
      autoEnrollKeys = {
        enable = true;
        autoReboot = false;
        includeMicrosoftKeys = true;
        includeFirmwareBuiltinKeys = true;
      };
    };
    initrd = {
      availableKernelModules = [
        "nvme" # For disk
        "xhci_pci" # For USB (but doesn't work?)
        "usb_storage"
        "sd_mod"
      ];
      secrets."/var/lib/measured-boot/fido2-fde-salt.luks" =
        "/run/agenix/paladin-iii/measured-boot/fido2-fde-salt.luks";
    };
    kernelParams = [
      "quiet"
    ];
  };

  # Ephemeral root: bind-mount persistent subvolumes (hardware-aspect/disk.nix)
  # into place. machine-id comes from a TPM credential, so it is not persisted.
  environment.persistence."/persist/states" = {
    hideMounts = true;
    # The only non-critical warning is that /var/lib/nixos is not persisted.
    # Userborn keeps UIDs/GIDs stable by reading the existing /etc/passwd and
    # /etc/group, which reset-root wipes, so accounts without a fixed uid/gid
    # are renumbered from scratch every boot. The numbers only shift when the
    # declared accounts change (e.g., a service added or removed); files those
    # accounts own on persistent storage would then have stale owners. diwangs
    # has a fixed uid. To fix properly: persist /var/lib/nixos (its own
    # subvolume) and set services.userborn.passwordFilesLocation to it.
    # Warnings are on if any entry enables them, so both entries disable them.
    enableWarnings = false;
    directories = [
      "/etc/nixos"
      "/etc/NetworkManager/system-connections"
      "/var/lib/bluetooth"
      "/var/lib/boltd"
      "/var/lib/systemd"
      {
        directory = "/home/diwangs";
        user = "diwangs";
        group = "users";
        mode = "0700";
      }
    ];
  };

  environment.persistence."/persist/caches" = {
    hideMounts = true;
    enableWarnings = false; # See the /var/lib/nixos note above
    directories = [
      "/var/cache"
      "/var/lib/flatpak"
      "/var/lib/pcrlock.d"
      "/var/log"
    ];
    # User-scoped persistence treats the home directory as a permissions
    # boundary. A system-level .cache entry copies its root-owned backing
    # parent's permissions onto /home/diwangs during every activation.
    users.diwangs.directories = [
      {
        directory = ".cache";
        mode = "0700";
      }
    ];
  };

  # Impermanence preserves existing backing-directory permissions, and the
  # /persist parents are created as root. Repair both homes and the cache
  # before Home Manager activation.
  systemd.tmpfiles.rules = [
    "d /persist/states/home/diwangs 0700 diwangs users - -"
    "d /persist/caches/home/diwangs 0700 diwangs users - -"
    "d /persist/caches/home/diwangs/.cache 0700 diwangs users - -"
  ];

  # TPM-based systemd-creds: machine-id
  # `lanzaboote` reads `/boot/loader/credentials` and store them in
  # `/run/credentials/@encrypted`, which are then read by `systemd-creds` to
  # feed PID 1 (hardcodes `system.machine_id` name). Since systemd 262, PID 1
  # Base64-decodes these, so install the Base64 text as-is (like pcrlock's).
  system.activationScripts.machineIdCredential.text = ''
    if ${pkgs.util-linux}/bin/mountpoint --quiet /boot; then
      ${pkgs.coreutils}/bin/install -D -m 0600 \
        ${pkgs.writeText "system.machine_id.cred" os-secret.systemd-creds.paladin-iii.machineIdBase64} \
        /boot/loader/credentials/system.machine_id.cred
    fi
  '';

  networking.hostName = "paladin-iii";
  networking.hostId = "cafebabe";

  # Framework Laptop are x86-only (for now...)
  nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";

  # Yubikey FIDO2 PAM
  # Register a new key with `pamu2fcfg`, then add its four fields - keyHandle,
  # publicKey, coseType, options - as another list below. pam_u2f keeps only
  # the *last* authfile line matching a user, so a user's credentials are
  # merged onto one colon-separated line at build time: a second `diwangs:`
  # line would silently shadow the first, not extend it.
  environment.etc."u2f_keys".text = lib.concatLines (
    lib.mapAttrsToList
      (
        user: creds:
        lib.concatStringsSep ":" ([ user ] ++ map (lib.concatStringsSep ",") creds)
      )
      {
        diwangs = [
          [
            "JT7oDmOJtCf5YOf9eyBBpKnApK2VnjpnvKp0kFv9pKWWr3ePPteBVxkNp3q5ZNQJFfjj22apnataR5qBzmmGjdFsIhwXFjRwiz8xR0eP4jD9VuEnJyG6PRC492i36qKhgCKfNoY8q4Rx5HQzQMe21hJ1RjKGOwfMvOaEQ1Li3BY="
            "sqzKcs2g+LQ2ptOI6dbFkBlqfEfWAjnigNjpMuxQnRQ="
            "eddsa"
            "+presence+pin"
          ]
        ];
      }
  );

  # TPM-sealed age identity, exposed only to agenix's private credential mount.
  # To replace it:
  # systemd-creds encrypt -T -p --name=age-identity <plaintext-identity> -
  systemd.services.agenix-install-secrets.serviceConfig.SetCredentialEncrypted =
    os-secret.systemd-creds.paladin-iii.ageIdentity;
  age.identityPaths = [
    "/run/credentials/agenix-install-secrets.service/age-identity"
  ];

  # Root secrets (decrypts to `/run/agenix/*`)
  age.secrets."paladin-iii/secure-boot/GUID".file =
    os-secret.paladin-iii.secure-boot.GUID;
  age.secrets."paladin-iii/secure-boot/keys/PK/PK.key".file =
    os-secret.paladin-iii.secure-boot.keys.PK."PK.key";
  age.secrets."paladin-iii/secure-boot/keys/PK/PK.pem".file =
    os-secret.paladin-iii.secure-boot.keys.PK."PK.pem";
  age.secrets."paladin-iii/secure-boot/keys/KEK/KEK.key".file =
    os-secret.paladin-iii.secure-boot.keys.KEK."KEK.key";
  age.secrets."paladin-iii/secure-boot/keys/KEK/KEK.pem".file =
    os-secret.paladin-iii.secure-boot.keys.KEK."KEK.pem";
  age.secrets."paladin-iii/secure-boot/keys/db/db.key".file =
    os-secret.paladin-iii.secure-boot.keys.db."db.key";
  age.secrets."paladin-iii/secure-boot/keys/db/db.pem".file =
    os-secret.paladin-iii.secure-boot.keys.db."db.pem";
  age.secrets."paladin-iii/measured-boot/fido2-fde-salt.luks".file =
    os-secret.paladin-iii.measured-boot."fido2-fde-salt.luks";

  # Consumed by ensure-printers (hardware/peripherals/printer.nix)
  age.secrets."network/malone-360-printer-uri".file =
    os-secret.network.malone-360-printer-uri;
}
