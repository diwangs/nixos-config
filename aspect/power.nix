#### Power
# - __Unlocked__
#     - Need PAM to `sudo`
# - __Locked__
#     - Need PAM to login
#     - Disk is unlocked
#     - Useful if left doing work
# - __Sleep__
#     - `luksSuspend` is called
#     - Disk is locked
#     - But RAM is still not cleared
#     - Useful if not doing work but need quick access
# - __Off__ -> fully off
#     - Disk is locked and RAM is cleared
#     - Useful if idle for a long time

# Hibernation is disabled due to security issues (ability to replace kernel)

{ config, lib, pkgs, ... }: {
	# Disable BT on boot
	hardware.bluetooth.powerOnBoot = false;

	powerManagement.enable = true;
	services.thermald.enable = true;

	# TLP (TLP PD replaces PPD)
	services.tlp = {
		enable = true;
		settings = {
			DEVICES_TO_DISABLE_ON_STARTUP = "wifi"; # Delayed, but no biggie
		};
	};
	services.tlp.pd.enable = true;
	services.power-profiles-daemon.enable = false; # Enabled in nixos-hardware

	# powerManagement.powertop.enable = true; # TODO: how to disable USB suspension?
	# boot.initrd.kernelModules = [ "cpufreq_stats" ]; # Load this at boot so powertop could do its job

	# services.xserver.displayManager.setupCommands = "${pkgs.brightnessctl}/bin/brightnessctl set 30% -d intel_backlight";
}