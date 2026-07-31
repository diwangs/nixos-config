{ pkgs, ... }: {
  # For Yubikey
  services.pcscd.enable = true; # conflicts with gpg's scdaemon
  services.udev.packages = [ pkgs.yubikey-personalization ];

  # An absolute authfile is read as root, which takes the mapping out of the
  # user-writable $HOME: a process running as the user can no longer append a
  # software authenticator to grant itself sudo/polkit. Leave `openasuser`
  # unset (every consumer here is root) and `nouserok` unset (with
  # `unixAuth = false` it would turn an unreadable file into an auth bypass).
  # security.pam.u2f.interactive = true;
  security.pam = {
    u2f.settings = {
      authfile = "/etc/u2f_keys"; # Content set in host-specific .nix
      cue = true;
    };
    services = {
      login.u2fAuth = true;
      login.unixAuth = false;
      gdm.fprintAuth = false;

      sudo.u2fAuth = true;
      sudo.unixAuth = false;

      polkit-1.u2fAuth = true;
      polkit-1.unixAuth = false;
    };
  };

  # Cosmetics
  services.displayManager.gdm.banner = "Password entry is disabled. Please use your FIDO2 authenticator.";
  security.sudo.extraConfig = ''
    		Defaults badpass_message="sudo: Password entry is disabled. Please use your FIDO2 authenticator."
    		Defaults passwd_tries="2"
    		Defaults timestamp_timeout=0
    	''; # Try twice so that message appears; never cache auth
}
