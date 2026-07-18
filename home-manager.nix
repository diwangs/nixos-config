# home-manager configuration for diwangs
{ config, pkgs, lib, agenix, ... }: {
	imports = [
		# Shared with rootless devboxes (shell + headless packages/agents)
		./home-manager.devbox.nix

		./aspect/desktop.hm.nix
		./aspect/yubikey.hm.nix

		./package/home-manager.nix
	];
}
