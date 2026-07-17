# home-manager configuration for diwangs
{ config, pkgs, lib, ... }: {
	imports = [
		# Shared with rootless devboxes (shell + headless packages/agents)
		./home-manager.devbox.nix

		./aspect/desktop.hm.nix
		./aspect/key-management.hm.nix

		./package/home-manager.nix
	];

	home.stateVersion = "25.05";
	home.username = "diwangs";
}
