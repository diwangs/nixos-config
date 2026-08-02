{ ... }: {
  services.userborn.enable = true;

  users = {
    mutableUsers = false;
    allowNoPasswordLogin = true; # Use FIDO2 exclusively
    users = {
      # Mark root account as locked
      root.hashedPassword = "!";

      # All machines share the same username
      diwangs = {
        isNormalUser = true;
        uid = 1000; # Stable runtime directory for the desktop SSH agent.
        # Disable password authentication for this user
        # NOTE: we don't use "!" because it disables GDM user list. Pay
        # attention to `nullok` in services still using `pam_unix`
        hashedPassword = "";
        extraGroups = [
          "wheel" # For ‘sudo’ and `iwd`.
          "networkmanager"
          "dialout" # Serial connection
          "adbusers" # Android debugging
          "plugdev" # HackRF
        ];
      };
    };
  };
}
