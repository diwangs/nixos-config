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
        # Pay attention to `nullok` in services still using `pam_unix`.
        hashedPassword = "*"; # Account is not locked but password is disabled
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
