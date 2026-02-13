{ config, pkgs, lib, ... }: {
	imports = [
    ../package/flatpak.nix
  ];
  
  services.flatpak = {
		enable = true;
		uninstallUnmanaged = true;
		overrides.global = {
			Context.sockets = [ "wayland" "!x11" "!fallback-x11" ];
		};
  };
}