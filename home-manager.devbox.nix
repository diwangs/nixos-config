# Shared home-manager entry: the strict subset of the laptop configuration
# (home-manager.nix imports this) that also serves as the standalone
# entry for rootless devboxes (flake.nix homeConfigurations). Devbox-specific
# config (genericLinux glue, headless extras, username) lives in flake.nix.
{ agenix, ... }: {
	imports = [
		agenix.homeManagerModules.default
		./aspect/shell.hm.nix

		./package/home-manager.devbox.nix
	];

	programs.home-manager.enable = true;

	home.enableNixpkgsReleaseCheck = false;
}
