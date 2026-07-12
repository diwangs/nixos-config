# Shared home-manager entry: the strict subset of the laptop configuration
# (system/home-manager.nix imports this) that also serves as the standalone
# entry for rootless devboxes (flake.nix homeConfigurations). Devbox-specific
# config (genericLinux glue, headless extras, username) lives in flake.nix.
{ config, pkgs, lib, ... }: {
	imports = [
		./aspect/shell.hm.nix

		../package/home-manager.devbox.nix
	];

	programs.home-manager.enable = true;

	home.enableNixpkgsReleaseCheck = false;
}
