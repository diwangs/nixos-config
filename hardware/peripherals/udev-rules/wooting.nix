{ config, lib, pkgs, ... }: {
	# services.udev.extraRules = ''
	# 	SUBSYSTEM=="hidraw", ATTRS{idVendor}=="31e3", TAG+="uaccess" 
	# 	SUBSYSTEM=="usb", ATTRS{idVendor}=="31e3", TAG+="uaccess"
	# '';

	# NOTE: uaccess needs priority < 73, but extraRules appends with priority 99
	# Temporary fix from https://github.com/NixOS/nixpkgs/issues/308681
	services.udev.packages = lib.singleton (pkgs.writeTextFile{ 
		name = "wooting-rules";
		text = ''
		SUBSYSTEM=="hidraw", ATTRS{idVendor}=="31e3", TAG+="uaccess"
		SUBSYSTEM=="usb", ATTRS{idVendor}=="31e3", TAG+="uaccess"
		'';
		destination = "/etc/udev/rules.d/70-wooting.rules";
	});
}