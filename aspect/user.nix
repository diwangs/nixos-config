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

          # Hermes' state tree is 2770 hermes:hermes and its gateway runs with
          # UMask 0007, so sharing sessions/skills/cron with this user is a group
          # membership. Upstream's module only wires that up for
          "hermes"
        ];

        # Not the 0700 default: ./agent.nix parks Hermes' `stateDir` at ~/Hermes
        # (persistent, unlike /var/lib on this host), and the `hermes` service user
        # has to traverse this home on every file access underneath it or the
        # gateway dies on EACCES. 0711 grants traverse only — other accounts still
        # can't list the home, though they can stat a path they already know.
        # It has to be declared here rather than chmod'd by hand: activation
        # re-applies `chown diwangs:users` + `chmod $homeMode` to the home on every
        # rebuild (nixpkgs' update-users-groups.pl), reverting anything manual.
        homeMode = "711";
      };
    };
  };
}
