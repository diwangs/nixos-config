# Edit this configuration file to define what should be installed on
# your system. Help is available in the configuration.nix(5) man page, on
# https://search.nixos.org/options and in the NixOS manual (`nixos-help`).

{ self, lib, pkgs, agenix, allowedUnfree, cua, nix-flatpak, ... }@args: {
	imports = [
		agenix.nixosModules.default
		cua.nixosModules.cua-driver
		nix-flatpak.nixosModules.nix-flatpak

		./aspect/audio.nix
		./aspect/locale.nix
		./aspect/network.nix
		./aspect/power.nix
		./aspect/user.nix
		./aspect/desktop.nix
		./aspect/virtualisation.nix
		./aspect/secret.nix
		./aspect/yubikey.nix

		./package/nixos.nix
    ./package/flatpak.nix
	];

	nixpkgs.overlays = [
		(import ./package/overlay/kernel/kernel.nix args).linuxKernel_7_1_3_hardenedOverlay
		(import ./package/overlay/fwupd/fwupd-pcrlock.nix)
		
		self.inputs.nix-vscode-extensions.overlays.default
		(import ./package/overlay/claude-code.nix)
		(import ./package/overlay/codex-acp.nix)

		# Official Anthropic Claude Desktop (repackaged .deb) + app.asar patches.
		# Migrated off patrickjaja's `claude-desktop-bin` (base + 9 patches); those
		# files remain under ./package/overlay/claude-desktop-bin/ for reference/
		# rollback but are no longer imported. Re-applied here: the OpenRouter/3p
		# patches (model-id, thinking-flag, titlegen, chat-effort) + debug-port +
		# the Cowork-VM path patch. Patrickjaja's Computer-Use/screenshot/ydotool
		# patches (05/08/10/11) are NOT migrated. Each patch runs its own
		# extract/repack or loose-file edit (see patch/lib.nix), so order is
		# irrelevant.
		(import ./package/overlay/claude-desktop/overlay.nix)
		(import ./package/overlay/claude-desktop/patch/debug-port-guard.nix)
		(import ./package/overlay/claude-desktop/patch/vm-path.nix)
		(import ./package/overlay/claude-desktop/patch/cli-path.nix)
		# (import ./package/overlay/claude-desktop/patch/3p/model-id-normalization.nix)
		# (import ./package/overlay/claude-desktop/patch/3p/thinking-flag.nix)
		# (import ./package/overlay/claude-desktop/patch/3p/titlegen-thinking.nix)
		# (import ./package/overlay/claude-desktop/patch/3p/chat-effort-toggle.nix)

	];

	nix.settings.experimental-features = [ "nix-command" "flakes" ];

	# Whitelist unfree packages
	# Define here instead of flake.nix to avoid replacing the whole pkgs
	nixpkgs.config.allowUnfreePredicate = pkg: builtins.elem (lib.getName pkg) allowedUnfree;

	# Replace stdenv with Clang/LLVM and compile with NixOS' hardening
	# This enables Clang-specific features (CFI) but disables GCC plugins (entropy, randstruct, structleak, and stackleak)
	boot.kernelPackages = pkgs.hardenedLinuxPackagesFor pkgs.linuxKernel.kernels.linux_7_1 (old: {
		stdenv = pkgs.withCFlags [ "-Wno-unused-command-line-argument" ] (import ./package/overlay/bintools.nix args).llvm;
		# stdenv = pkgs.withCFlags [ "-Wno-unused-command-line-argument" ] pkgs.llvmPackages.stdenv;

		extraMakeFlags = [ "LLVM=1" ];	# Use all LLVM bintools instead of just Clang
		ignoreConfigErrors = true;			# Some GCC-specific hardening (e.g. GCC_PLUGINS) are set as non-optionally yes
	});

	# Kernel LSM support:
	# Exclusive LSM: NixOS doesn't really have a strong implementation: no SELinux, AppArmor has limited profile (due to non-FHS)
	# Stackable LSM: capability,landlock,yama,safesetid,bpf. No loadpin (fine since it's not embedded), lockdown, or integrity
	boot.kernelPatches = [
		{
			name = "patch";
			patch = null;
			structuredExtraConfig = with lib.kernel; {	# Not to be confused with `structuedExtraConfig`, what a horrible naming scheme
				# Lockdown will deter firmware update on Chromebook
				SECURITY_LOCKDOWN_LSM = lib.mkForce yes; 	# Get kernel ready for lockdown mode
				
				MODULE_SIG = lib.mkForce yes;							# Generate key, sign module, dump the private part
				# TODO: MODULE_SIG_FORCE?
				DEVMEM = lib.mkForce no; # /dev/mem: disable, not needed for 7040
				# Options for BIOS access for Chromebook
				# STRICT_DEVMEM = lib.mkForce yes;
				# IO_STRICT_DEVMEM = no;

				# Compiler
				LTO_CLANG_FULL = yes;			# Enable full ClangLTO optimization (full). Note that since kCFI, this doesn't have any security benefit
			};
		}
	];

	# Enabling LSM
	security.apparmor.enable = true;
	security.lsm = [ "lockdown" ];
	boot.kernelParams = [ "lockdown=integrity" ]; # TODO: try confidentiality

	# Hardened profile doesn't allow this?
	services.logrotate.checkConfig = false;
	security.rtkit.enable = true;

	# nix-ld: for packages that hasn't been nixified
  # e.g., `fw-ectool` and virtualhere
  programs.nix-ld.enable = true;
	# programs.nix-ld.libraries = with pkgs; [
	# 	libusb1			# For firmware updates with SuzyQ
	# ];

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

	services.flatpak = {
		enable = true;
		uninstallUnmanaged = true;
		overrides.global = {
			Context.sockets = [ "wayland" "!x11" "!fallback-x11" ];
		};
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
