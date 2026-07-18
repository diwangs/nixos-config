{ config, lib, pkgs, modulesPath, ... }: {
  # Intel CPU
	hardware.cpu.intel.updateMicrocode = lib.mkDefault config.hardware.enableRedistributableFirmware;
	boot.kernelModules = [ "kvm-intel" ];

  # Enable TB on the upper-left port for dock
	systemd.services."cros-ec-dock" = {
		enable = true;
		restartIfChanged = false;
		serviceConfig = {
			ExecStart = "${pkgs.fw-ectool}/bin/ectool typeccontrol 3 2 1";
			RemainAfterExit = true;
		};
		wantedBy = [ "multi-user.target" ];
	};
}