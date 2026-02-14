{ config, pkgs, lib, secrets, ... }: {
	users.mutableUsers = false;

	# Root (Generate with `mkpasswd`)
	users.users.root.initialHashedPassword = secrets.diwangs.hashed-password;

  # Define a user account. Don't forget to set a password with ‘passwd’.
	users.users.diwangs = {
		isNormalUser = true;
		extraGroups = [ 
			"wheel" 		# For ‘sudo’ and `iwd`.
			"networkmanager"
			"dialout"		# Serial connection
			"adbusers"	# Android debugging
			"plugdev"		# HackRF
		]; 
		initialHashedPassword = secrets.diwangs.hashed-password;		# Enable for GDM to detect it?
		# NOTE: The same password is used for Gnome keyring, but is not synced
		shell = pkgs.zsh; # Enable here but manage at package/home-manager.nix
		ignoreShellProgramCheck = true;
	};
}