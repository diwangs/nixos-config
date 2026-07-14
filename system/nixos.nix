# Edit this configuration file to define what should be installed on
# your system. Help is available in the configuration.nix(5) man page, on
# https://search.nixos.org/options and in the NixOS manual (`nixos-help`).

{ self, config, lib, pkgs, allowedUnfree, cua, ... }: {
	imports = [
		./aspect/audio.nix
		./aspect/locale.nix
		./aspect/network.nix
		./aspect/performance.nix
		./aspect/power.nix
		./aspect/security.nix
		./aspect/user.nix
		./aspect/desktop.nix
		./aspect/key-management.nix
		./aspect/virtualisation.nix
		./aspect/secret.nix

		../package/nixos.nix
	];

	nixpkgs.overlays = [
		self.inputs.nix-vscode-extensions.overlays.default
		(import ../package/overlay/claude-code.nix)

		# Official Anthropic Claude Desktop (repackaged .deb) + app.asar patches.
		# Migrated off patrickjaja's `claude-desktop-bin` (base + 9 patches); those
		# files remain under ../package/overlay/claude-desktop-bin/ for reference/
		# rollback but are no longer imported. Re-applied here: the OpenRouter/3p
		# patches (model-id, thinking-flag, titlegen, chat-effort) + debug-port +
		# the Cowork-VM path patch. Patrickjaja's Computer-Use/screenshot/ydotool
		# patches (05/08/10/11) are NOT migrated. Each patch runs its own
		# extract/repack or loose-file edit (see patch/lib.nix), so order is
		# irrelevant.
		(import ../package/overlay/claude-desktop/overlay.nix)
		(import ../package/overlay/claude-desktop/patch/debug-port-guard.nix)
		(import ../package/overlay/claude-desktop/patch/vm-path.nix)
		(import ../package/overlay/claude-desktop/patch/cli-path.nix)
		# (import ../package/overlay/claude-desktop/patch/3p/model-id-normalization.nix)
		# (import ../package/overlay/claude-desktop/patch/3p/thinking-flag.nix)
		# (import ../package/overlay/claude-desktop/patch/3p/titlegen-thinking.nix)
		# (import ../package/overlay/claude-desktop/patch/3p/chat-effort-toggle.nix)

	];

	nix.settings.experimental-features = [ "nix-command" "flakes" ];

	# Whitelist unfree packages
	# Define here instead of flake.nix to avoid replacing the whole pkgs
	nixpkgs.config.allowUnfreePredicate = pkg: builtins.elem (lib.getName pkg) allowedUnfree;

	# nix-ld: for packages that hasn't been nixified
  # e.g., `fw-ectool` and virtualhere
  programs.nix-ld.enable = true;
	# programs.nix-ld.libraries = with pkgs; [
	# 	libusb1			# For firmware updates with SuzyQ
	# ];

	security.rtkit.enable = true;

	# NOTE: the official Claude Desktop bundles and self-spawns its own Cowork
	# backend (cowork-linux-helper, restart-backoff supervised, in-$HOME rpc.sock),
	# so patrickjaja's external `services.claude-cowork` daemon was removed in the
	# migration — it's no longer used.

	# Enable cua-driver (also sets CUA_DRIVER_BIN)
	#
	# NOTE: this does not start a daemon, since the intended design is to spawn 
	# on-demand for MCP.
	services.cua-driver = {
		enable = true;
		package = cua.packages.${pkgs.stdenv.hostPlatform.system}.cua-driver;
	};

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
