{ pkgs, agenix, ... }: {
  # oo7: Secret Portal and Secret Service
  services.oo7.enable = true;
  services.gnome.gnome-keyring.enable = false;
  # Drop-in to oo7-daemon to enable auto-unlock via agenix at login
  systemd.user.services.oo7-daemon = {
    after = [ "agenix.service" ];
    wants = [ "agenix.service" ];
    serviceConfig.ImportCredential = ""; # Don't use systemd-creds
    # Make sure there's a file called `oo7.keyring-encryption-password` here
    environment.CREDENTIALS_DIRECTORY = "/run/user/1000/agenix/paladin-iii";
  };

  # SSH: we use yubikey-agent
  programs.ssh.enableAskPassword = true; # export SSH_ASKPASS
  services.gnome.gcr-ssh-agent.enable = false; # disable GCR SSH agent (25.11)

  # agenix: general secret management

  # Unlike HM, this doesn't depend on UID
  # Make sure it resides in a mountpoint that is `neededForBoot`
  # If it is ever changed, be sure to switch twice for measured boot
  age.identityPaths = [ "/nix/secret/.age-identity" ];

  # Mainline Go `age`, which is also agenix's default for both the module and
  # the CLI — so no `age.ageBin` and no package override here, and the two can't
  # drift apart. This used to pin rage (Rust) instead; rage lost that job when
  # we went post-quantum.
  #
  # Only Go `age` implements the X-Wing hybrid recipient type from the age spec
  # (`age1pq1..` recipients, `AGE-SECRET-KEY-PQ-1..` identities, stanza
  # `mlkem768x25519`), which is the *only* software identity whose recipients
  # carry the `postquantum` label. That label is what lets a secret name both
  # this host and a YubiKey `age1tagpq1..` recipient: age refuses to encrypt a
  # file to a labelled recipient alongside an unlabelled one, since a classical
  # stanza in the same file would undo the post-quantum guarantee.
  #
  # rage 0.12.1 can encrypt to `age1tag1..`/`age1tagpq1..` hardware recipients
  # but has no post-quantum identity of its own — it rejects the identity file
  # outright ("identity file contains non-identity data"). str4d/rage#632 adds
  # one, but it's still a draft blocked on RustCrypto/KEMs#364. Switching back
  # is a one-line change if it lands: the file format is identical, so nothing
  # needs re-encrypting.
  #
  # ./secret.hm.nix never overrode this, so the home-manager layer has
  # been on Go `age` all along; this just ends the split.

  # agenix CLI + YubiKey plugin for editing/encrypting secrets on this host
  environment.systemPackages = [
    agenix.packages.${pkgs.stdenv.hostPlatform.system}.default
    # For manual decrypt/inspect (matches what boot activation runs), and for
    # `age-keygen -pq` to mint the post-quantum host identity.
    pkgs.age
    pkgs.age-plugin-yubikey
  ];
}
