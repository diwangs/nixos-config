{ pkgs, agenix, agenix-secrets, ... }: {
  # Secret management (agenix)
  # Runtime-only: secrets decrypt at activation into /run/agenix/*. Eval-time
  # values (partition UUIDs, hostnames, keygrips, ...) stay in secret.toml.
  #
  # Two identities, every .age file is encrypted to both (secrets/secret.nix):
  # - Machine (unattended decrypt at boot): dedicated host key below, NOT in
  #   git, no sshd involved. Back it up offline.
  # - Human (agenix -e): YubiKey PIV P-256 via age-plugin-yubikey.
  systemd.tmpfiles.rules = [ "d /nix/secret 0700 root root -" ];
  age.identityPaths = [ "/nix/secret/host.key" ];

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

  # .age files come from the private agenix-secrets flake input; register new
  # ones there (flake.nix lib.age + secret.nix recipients), then here.
  # Consume via config.age.secrets."<name>".path (decrypts to /run/agenix/*).

  age.secrets."paladin-iii-machine-id" = {
    file = agenix-secrets.lib.age.paladin-iii-machine-id;
    mode = "0444";   # machine-id must be world-readable (dbus, user sessions, NM)
  };
  # Regular file at the canonical path, ordered after agenix decryption
  system.activationScripts.machineId = {
    deps = [ "agenix" ];
    text = ''
      install -m 0444 /run/agenix/paladin-iii-machine-id /etc/machine-id
    '';
  };

  # Decrypted at activation, before user creation (agenix orders itself
	# ahead of the `users` activation script for root-owned secrets).
	age.secrets."hashed-password".file = agenix-secrets.lib.age.hashed-password;
	age.secrets."bedrock-token" = {
    file = agenix-secrets.lib.age.bedrock-token;
    owner = "diwangs";
  };

	# Consumed by ensure-printers (hardware/peripherals/printer.nix)
	age.secrets."malone-360-printer-uri".file = agenix-secrets.lib.age.malone-360-printer-uri;
	age.secrets."ssh-hosts" = {
    file = agenix-secrets.lib.age.ssh-hosts;
    owner = "diwangs";
  };
  age.secrets."diwangs-nova.pem" = {
    file = agenix-secrets.lib.age."diwangs-nova.pem";
    owner = "diwangs";
  };
}
