{ pkgs, lib, ... }: {
  # For Yubikey
  services.pcscd.enable = true; # conflicts with gpg's scdaemon
  services.udev.packages = [ pkgs.yubikey-personalization ];
  # age identity plugin for editing secrets (agenix CLI is in aspect/secret.nix)
  environment.systemPackages = [ pkgs.age-plugin-yubikey ];

  # nixos-hardware's framework-13 profile enables fprintd, which materialises
  # two auth paths that never reach `pam_u2f`: the `gdm-fingerprint` service
  # (fingerprint only - this is what GNOME offers alongside the password entry
  # at the greeter and the lock screen whenever a reader is present) and a
  # `pam_fprintd` sufficient line in `polkit-1`. Nothing is enrolled on the
  # Goodix sensor today, so neither is currently a way in, but an enrollment
  # would silently become one. Drop the reader rather than patch each stack.
  services.fprintd.enable = lib.mkForce false;

  # An absolute authfile is read as root, which takes the mapping out of the
  # user-writable $HOME: a process running as the user can no longer append a
  # software authenticator to grant itself sudo/polkit. Leave `openasuser`
  # unset (every consumer here is root) and `nouserok` unset (with
  # `unixAuth = false` it would turn an unreadable file into an auth bypass).
  # security.pam.u2f.settings.interactive = true;
  security.pam = {
    u2f.settings = {
      authfile = "/etc/u2f_keys"; # Content set in host-specific .nix
      cue = true;
    };
    services = {
      login.u2f.enable = true;
      login.unixAuth = false;
      gdm.fprintAuth = false;

      sudo.u2f.enable = true;
      sudo.unixAuth = false;

      polkit-1.u2f.enable = true;
      polkit-1.unixAuth = false;
    };
  };

  # polkit >= 127 runs its PAM helper as a sandboxed, socket-activated unit
  # (`PrivateDevices=yes`, `DevicePolicy=strict`), which hides /dev/hidraw*
  # from pam_u2f. With `unixAuth = false` every polkit auth (incl. `run0`)
  # then fails instantly. Expose hidraw (plus RNG) devices to the helper.
  systemd.services."polkit-agent-helper@".serviceConfig = {
    PrivateDevices = false;
    # Turning off PrivateDevices also drops its implicit allowlist, and
    # pam_u2f reads /dev/urandom to build the challenge.
    DeviceAllow = [
      "char-hidraw rw"
      "/dev/urandom r"
    ];
  };

  # Cosmetics
  services.displayManager.gdm.banner = "Password entry is disabled. Please use your FIDO2 authenticator.";
  security.sudo.extraConfig = ''
    		Defaults badpass_message="sudo: Password entry is disabled. Please use your FIDO2 authenticator."
    		Defaults passwd_tries="2"
    		Defaults timestamp_timeout=0
    	''; # Try twice so that message appears; never cache auth
}
