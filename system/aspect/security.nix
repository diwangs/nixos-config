{ config, lib, pkgs, ... }@args: {
	boot.loader.efi.canTouchEfiVariables = true;
	
	# ======
	# Kernel
	# ======

	# Use hardened stable kernel compiled with Clang/LLVM toolchain
	# This is sometimes a bit behind the latest stable (up to a month) if there
	# is new major version (e.g., 6.17 -> 6.18)
	# NOTE: this is currently not used because it prevents update of the entire nixpkgs
	# when the old version got deprecated.
	# Currently using latest LTS instead, so that I could update the rest of the system
	# nixpkgs.overlays = [ (import ./lib/kernel.nix args).linuxKernel_6_17_13_hardenedOverlay ];

	# Replace stdenv with Clang/LLVM and compile with NixOS' hardening
	# This enables Clang-specific features (CFI) but disables GCC plugins (entropy, randstruct, structleak, and stackleak)
	# TODO: modularize kernel overrides
	boot.kernelPackages = pkgs.hardenedLinuxPackagesFor pkgs.linuxKernel.kernels.linux_6_12 (old: {
		stdenv = pkgs.withCFlags [ "-Wno-unused-command-line-argument" ] (import ./lib/bintools.nix args).llvm;
		# stdenv = pkgs.withCFlags [ "-Wno-unused-command-line-argument" ] pkgs.llvmPackages.stdenv;

		extraMakeFlags = [ "LLVM=1" ];	# Use all LLVM bintools instead of just Clang
		ignoreConfigErrors = true;			# Some GCC-specific hardening (e.g. GCC_PLUGINS) are set as non-optionally yes
	});

	# =====
	# LSM
	# =====

	# Kernel support:
	# Exclusive LSM: NixOS doesn't really have a strong implementation: no SELinux, AppArmor has limited profile (due to non-FHS)
	# Stackable LSM: capability,landlock,yama,safesetid,bpf. No loadpin (fine since it's not embedded), lockdown, or integrity
	boot.kernelPatches = [
		{
			name = "lsm-patch";
			patch = null;
			structuredExtraConfig = with lib.kernel; {	# Not to be confused with `structuedExtraConfig`, what a horrible naming scheme
				MODULE_SIG = lib.mkForce yes;							# Generate key, sign module, dump the private part
				# SECURITY_LOCKDOWN_LSM = lib.mkForce yes; 	# Get kernel ready for lockdown mode

				# /dev/mem: strict but enable BIOS access for Chromebook firmware update
				DEVMEM = yes;
				STRICT_DEVMEM = lib.mkForce yes;
				IO_STRICT_DEVMEM = no;
			};
		}
	];

	# Lockdown will deter firmware update

	# =======
	# Runtime
	# =======

	# Enabling LSM
	security.apparmor.enable = true;

	# Yubikey U2F PAM
	# known_keys are located in .config/Yubico/u2fkeys
	# Add key with `pamu2fcfg`
	security.pam.u2f.settings.cue = true;
	# security.pam.u2f.interactive = true;
	services.displayManager.gdm.banner = "Password entry is disabled. Please use your FIDO2 authenticator.";
	security.pam.services = {
		login.u2fAuth = true;
		login.unixAuth = false;
		
		sudo.u2fAuth = true;
		sudo.unixAuth = false;

		gdm.fprintAuth = false;
		gdm.enableGnomeKeyring = true;
	};
	# Passwd_tries 2 so that message appears
	security.sudo.extraConfig = ''
		Defaults badpass_message="sudo: Password entry is disabled. Please use your FIDO2 authenticator."
		Defaults passwd_tries="2"
	'';
	# TODO: gnome-keyring must be unlocked separately

	# Enable unprivileged user NS
	# Historically this allows for some CVE, but a bunch of packages rely on this (e.g. chromium-based, Zoom, etc.)
	security.unprivilegedUsernsClone = true;

	# Hardened profile doesn't allow this?
	services.logrotate.checkConfig = false;

	# =======
	# Network
	# =======
	networking.networkmanager.wifi.macAddress = "random";	# Prevent tracking via MAC address


	# USBGuard?
}
