{ config, pkgs, ... }: {
	users.mutableUsers = false;

	# Root (Generate with `mkpasswd`)
	users.users.root.hashedPasswordFile = config.age.secrets."paladin-iii/hashed-password".path;

  # Define a user account. Don't forget to set a password with ‘passwd’.
	users.users.diwangs = {
		isNormalUser = true;
		uid = 1000;  # Stable runtime directory for the desktop SSH agent.
		extraGroups = [
			"wheel" 		# For ‘sudo’ and `iwd`.
			"networkmanager"
			"dialout"		# Serial connection
			"adbusers"	# Android debugging
			"plugdev"		# HackRF
		];
		hashedPasswordFile = config.age.secrets."paladin-iii/hashed-password".path;	# Enable for GDM to detect it?
		# NOTE: The same password is used for Gnome keyring, but is not synced
		shell = pkgs.zsh; # Enable here but manage at package/home-manager.nix
		ignoreShellProgramCheck = true;
	};
}
