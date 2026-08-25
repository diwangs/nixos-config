# For Framework 13 (for Chromebook and 7040 boards)
{
  lib,
  pkgs,
  os-secret,
  lanzaboote,
  nixos-hardware,
  ...
}:
{
  imports = [
    # Laptop hardware
    # Semi-portable configs
    lanzaboote.nixosModules.lanzaboote
    nixos-hardware.nixosModules.framework-13-7040-amd

    ./hardware-aspect/mainboard-7040.nix
    ./hardware-aspect/disk.nix
    ./hardware-aspect/measured-boot.nix
    ./hardware-aspect/kensington-infinity-dock.nix
    ./hardware-aspect/thunderbolt-initrd.nix
    ./hardware-aspect/printer.nix
  ];

  # Enable non-free firmware (Qualcomm NCM865, Radeon, NPU, etc.)
  # This is defined in `not-detected.nix`, but let's define explicitly
  hardware.enableRedistributableFirmware = lib.mkDefault true;

  # Sensors for auto-brightness
  hardware.sensor.iio.enable = true;

  # Framework Laptop are x86-only (for now...)
  nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";

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
      configurationLimit = 5; # Limit is 8. Each initrd is ~62MB;
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

  networking.hostName = "paladin-iii";
  networking.hostId = "cafebabe";

  # Peripherals
  hardware.hackrf.enable = true;
  hardware.wooting.enable = true; # This requires unfree license

  # TPM-based systemd-creds: machine-id
  # `lanzaboote` reads `/boot/loader/credentials` and store them in
  # `/run/credentials/@encrypted`, which are then read by `systemd-creds` to
  # feed PID 1 (hardcodes `system.machine_id` name)
  system.activationScripts.machineIdCredential.text = ''
    if ${pkgs.util-linux}/bin/mountpoint --quiet /boot; then
      ${pkgs.coreutils}/bin/install -D -m 0600 \
        ${
          pkgs.runCommandLocal "system.machine_id.cred" { } ''
            ${pkgs.coreutils}/bin/base64 --decode ${pkgs.writeText "system.machine_id.cred.base64" os-secret.systemd-creds.paladin-iii.machineIdBase64} > "$out"
          ''
        } \
        /boot/loader/credentials/system.machine_id.cred
    fi
  '';

  # TPM-sealed age identity, exposed only to agenix's private credential mount.
  # To replace it:
  # systemd-creds encrypt -T -p --name=age-identity <plaintext-identity> -
  systemd.services.agenix-install-secrets.serviceConfig.SetCredentialEncrypted =
    os-secret.systemd-creds.paladin-iii.ageIdentity;

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

  # age.secrets."paladin-iii/hashed-password".file =
  #   os-secret.paladin-iii.hashed-password;

  # Consumed by ensure-printers (hardware/peripherals/printer.nix)
  age.secrets."network/malone-360-printer-uri".file =
    os-secret.network.malone-360-printer-uri;

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
}
