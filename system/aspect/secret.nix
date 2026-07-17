{ pkgs, agenix, age-secrets, ... }: {
  # Secret management (agenix)
  # Runtime-only: secrets decrypt at activation into /run/agenix/*. Eval-time
  # values (partition UUIDs, hostnames, keygrips, ...) stay in secret.toml.
  #
  # Every .age file is encrypted to both identities (secrets/secret.nix):
  # - Machine (unattended decrypt at boot): dedicated host key, configured in
  #   flake.nix, NOT in git, no sshd involved. Back it up offline.
  # - Human (agenix -e): YubiKey PIV P-256 via age-plugin-yubikey.
  systemd.tmpfiles.rules = [ "d /nix/secret 0700 root root -" ];

  # Use rage (Rust) instead of Go age, for both boot-time decryption and the
  # editing CLI. Same format + plugin protocol, so .age files are unaffected.
  age.ageBin = "${pkgs.rage}/bin/rage";

  # agenix CLI + YubiKey plugin for editing/encrypting secrets on this host
  environment.systemPackages = [
    (agenix.packages.${pkgs.stdenv.hostPlatform.system}.default.override {
      ageBin = "${pkgs.rage}/bin/rage";
    })
    pkgs.rage # for manual decrypt/inspect (matches what boot activation runs)
    pkgs.age-plugin-yubikey
  ];

  # Root secrets (decrypts to `/run/agenix/*`)
  age.secrets."paladin-iii/secure-boot/GUID".file = age-secrets.paladin-iii.secureboot.GUID;
  age.secrets."paladin-iii/secure-boot/keys/PK/PK.key".file = age-secrets.paladin-iii.secureboot.keys.PK."PK.key";
  age.secrets."paladin-iii/secure-boot/keys/PK/PK.pem".file = age-secrets.paladin-iii.secureboot.keys.PK."PK.pem";
  age.secrets."paladin-iii/secure-boot/keys/KEK/KEK.key".file = age-secrets.paladin-iii.secureboot.keys.KEK."KEK.key";
  age.secrets."paladin-iii/secure-boot/keys/KEK/KEK.pem".file = age-secrets.paladin-iii.secureboot.keys.KEK."KEK.pem";
  age.secrets."paladin-iii/secure-boot/keys/db/db.key".file = age-secrets.paladin-iii.secureboot.keys.db."db.key";
  age.secrets."paladin-iii/secure-boot/keys/db/db.pem".file = age-secrets.paladin-iii.secureboot.keys.db."db.pem";
  age.secrets."paladin-iii/measured-boot/fido2-fde-salt.luks".file = age-secrets.paladin-iii.measured-boot."fido2-fde-salt.luks";

  age.secrets."paladin-iii/machine-id" = {
    file = age-secrets.paladin-iii.machine-id;
    mode = "0444";   # machine-id must be world-readable (dbus, user sessions, NM)
  };

  # Regular file at the canonical path, ordered after agenix decryption
  system.activationScripts.machineId = {
    deps = [ "agenix" ];
    text = ''
      install -m 0444 /run/agenix/paladin-iii/machine-id /etc/machine-id
    '';
  };

	age.secrets."paladin-iii/hashed-password".file = age-secrets.paladin-iii.hashed-password;

	# Consumed by ensure-printers (hardware/peripherals/printer.nix)
	age.secrets."network/malone-360-printer-uri".file = age-secrets.network.malone-360-printer-uri;
  
  
  # User secrets (should decrypt to `/run/user/$UID/agenix/*`)
  # Decrypted at activation, before user creation (agenix orders itself
	# ahead of the `users` activation script for root-owned secrets).
  age.secrets."network/ssh-hosts" = {
    file = age-secrets.network.ssh-hosts;
    owner = "diwangs";
  };
  age.secrets."network/diwangs-nova.pem" = {
    file = age-secrets.network."diwangs-nova.pem";
    owner = "diwangs";
  };
  age.secrets."token/bedrock" = {
    file = age-secrets.token.bedrock;
    owner = "diwangs";
  };
}
