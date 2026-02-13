# Underlying hardware: 
# - Razer Core X
# - Radeon 7800XT
# Static switching: sacrifice hot-plugging for performance

{ config, lib, pkgs, ... }:

{
	specialisation = {
		egpu.configuration = {
			system.nixos.tags = [ "egpu" ];
            
			boot = {
				initrd.kernelModules = [ "amdgpu" ];
				blacklistedKernelModules = [ "i915" ];

				kernelParams = [
						"module_blacklist=i915"
				];
			};

			services.xserver.videoDrivers = [ "amdgpu" ];

			# Change the tbt status in port 0
			systemd.services."cros-ec-tbt" = {
				enable = true;
				restartIfChanged = false;
				serviceConfig = {
					ExecStart = "${pkgs.fw-ectool}/bin/ectool typeccontrol 0 2 1";
					RemainAfterExit = true;
				};
				wantedBy = [ "multi-user.target" ];
			};
		};
	};
}