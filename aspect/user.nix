{ config, pkgs, ... }: {
  users.mutableUsers = false;
  programs.zsh.enable = true; # Add to /etc/shells; enables user in greeter

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
    # NOTE: GNOME Keyring traditionally uses the same password, but not synced
    # We don't use it anymore, but just note it here for reference.
    hashedPasswordFile = config.age.secrets."paladin-iii/hashed-password".path;
    shell = pkgs.zsh; # Set default shell; further config goes to home-manager
  };
}
