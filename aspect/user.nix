{ config, lib, ... }: {
  users.mutableUsers = false;

  # Root (Generate with `mkpasswd`)
  users.users.root.hashedPasswordFile =
    config.age.secrets."paladin-iii/hashed-password".path;

  # Define a user account. Don't forget to set a password with ‘passwd’.
  users.users.diwangs = {
    isNormalUser = true;
    uid = 1000; # Stable runtime directory for the desktop SSH agent.
    extraGroups = [
      "wheel" # For ‘sudo’ and `iwd`.
      "networkmanager"
      "dialout" # Serial connection
      "adbusers" # Android debugging
      "plugdev" # HackRF
    ];
    # NOTE: GNOME Keyring traditionally uses the same password, but not synced.
    # We don't use it anymore, but just note it here for reference.
    hashedPasswordFile = config.age.secrets."paladin-iii/hashed-password".path;
  };

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
