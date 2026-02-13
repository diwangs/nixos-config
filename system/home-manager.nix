# home-manager configuration for diwangs
{ config, pkgs, lib, ... }: {
	imports = [
		./aspect/desktop.hm.nix
		./aspect/key-management.hm.nix

		../package/home-manager.nix
	];

	programs.home-manager.enable = true;
	
	home.stateVersion = "25.05";
	home.username = "diwangs";
	home.enableNixpkgsReleaseCheck = false;
}
