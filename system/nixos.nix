# Edit this configuration file to define what should be installed on
# your system. Help is available in the configuration.nix(5) man page, on
# https://search.nixos.org/options and in the NixOS manual (`nixos-help`).

{ self, config, lib, pkgs, allowedUnfree, ... }: {
	imports = [
		./aspect/audio.nix
		./aspect/locale.nix
		./aspect/network.nix
		./aspect/performance.nix
		./aspect/power.nix
		./aspect/security.nix
		./aspect/users.nix
		./aspect/desktop.nix
		./aspect/key-management.nix

		../package/nixos.nix
	];

	nixpkgs.overlays = [
		self.inputs.nix-vscode-extensions.overlays.default

		# Expose claude-cowork-service (Cowork's native Linux backend) as a
		# package. The flake has no overlays.default, so pull it from its
		# per-system packages output. Enabled as a user service + added to
		# home.packages in package/home-manager.nix.
		(final: prev: {
			claude-cowork-service =
				self.inputs.claude-cowork-service.packages.${final.stdenv.hostPlatform.system}.claude-cowork-service;
		})

		# Claude Desktop 3p (OpenRouter). `base.nix` constructs `claude-desktop`
		# from patrickjaja's package.nix; each ./patches/*.nix is an INDEPENDENT
		# overlay layering one OpenRouter/Computer-Use patch on top. They commute
		# (per-fragment extract/repack), so add, remove, or reorder the patch
		# imports freely — but keep base.nix first. See ../package/overlay/claude-desktop-bin.
		(import ../package/overlay/claude-desktop-bin/base.nix { inherit self; })
		(import ../package/overlay/claude-desktop-bin/patches/01-debug-port-guard.nix)
		(import ../package/overlay/claude-desktop-bin/patches/3p/02-model-id-normalization.nix)
		(import ../package/overlay/claude-desktop-bin/patches/3p/03-thinking-toggle-flag.nix)
		(import ../package/overlay/claude-desktop-bin/patches/3p/04-titlegen-thinking.nix)
		(import ../package/overlay/claude-desktop-bin/patches/patrickjaja/05-computer-use-flags.nix)
		(import ../package/overlay/claude-desktop-bin/patches/patrickjaja/06-force-xdotool-under-xwayland.nix)
		(import ../package/overlay/claude-desktop-bin/patches/3p/07-chat-effort-toggle.nix)
		(import ../package/overlay/claude-desktop-bin/patches/patrickjaja/08-screenshot-downsample.nix)
	];

	nix.settings.experimental-features = [ "nix-command" "flakes" ];

	# nix-ld: for packages that hasn't been nixified
  # e.g., `fw-ectool` and virtualhere
  programs.nix-ld.enable = true;
	# programs.nix-ld.libraries = with pkgs; [
	# 	libusb1			# For firmware updates with SuzyQ
	# ];

	security.rtkit.enable = true;

	# Whitelist unfree packages
	# Define here instead of flake.nix to avoid replacing the whole pkgs
	nixpkgs.config.allowUnfreePredicate = pkg: builtins.elem (lib.getName pkg) allowedUnfree;

	# Configure keymap in X11
	# services.xserver.xkb.layout = "us";
	# services.xserver.xkb.options = "eurosign:e,caps:escape";

	# Copy the NixOS configuration file and link it from the resulting system
	# (/run/current-system/configuration.nix). This is useful in case you
	# accidentally delete configuration.nix.
	# system.copySystemConfiguration = true;

	# This option defines the first version of NixOS you have installed on this particular machine,
	# and is used to maintain compatibility with application data (e.g. databases) created on older NixOS versions.
	#
	# Most users should NEVER change this value after the initial install, for any reason,
	# even if you've upgraded your system to a new NixOS release.
	#
	# This value does NOT affect the Nixpkgs version your packages and OS are pulled from,
	# so changing it will NOT upgrade your system.
	#
	# This value being lower than the current NixOS release does NOT mean your system is
	# out of date, out of support, or vulnerable.
	#
	# Do NOT change this value unless you have manually inspected all the changes it would make to your configuration,
	# and migrated your data accordingly.
	#
	# For more information, see `man configuration.nix` or https://nixos.org/manual/nixos/stable/options#opt-system.stateVersion .
	system.stateVersion = "23.11"; # Did you read the comment?
}
