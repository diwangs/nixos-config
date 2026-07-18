{ config, lib, pkgs, ... }: {
  # For Yubikey
  services.pcscd.enable = true; # conflicts with gpg's scdaemon
  services.udev.packages = [ pkgs.yubikey-personalization ];

  # Yubikey FIDO2 PAM
	# known_keys are located in .config/Yubico/u2fkeys
	# Add key with `pamu2fcfg`
	security.pam.u2f.settings.cue = true;
	# security.pam.u2f.interactive = true;
	services.displayManager.gdm.banner = "Password entry is disabled. Please use your FIDO2 authenticator.";
	security.pam.services = {
		login.u2fAuth = true;
		login.unixAuth = false;
		
		sudo.u2fAuth = true;
		sudo.unixAuth = false;

		gdm.fprintAuth = false;
		gdm.enableGnomeKeyring = true;
	};
	# passwd_tries 2 so that message appears
	security.sudo.extraConfig = ''
		Defaults badpass_message="sudo: Password entry is disabled. Please use your FIDO2 authenticator."
		Defaults passwd_tries="2"
	'';
}