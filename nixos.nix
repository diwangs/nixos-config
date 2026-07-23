# Edit this configuration file to define what should be installed on
# your system. Help is available in the configuration.nix(5) man page, on
# https://search.nixos.org/options and in the NixOS manual (`nixos-help`).

{
  self,
  lib,
  pkgs,
  agenix,
  allowedUnfree,
  cua,
  nix-flatpak,
  ...
}@args:
{
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
    ./aspect/shell.nix
    ./aspect/yubikey.nix

    ./package/nixos.nix
    ./package/flatpak.nix
  ];

  nixpkgs.overlays = [
    (import ./package/overlay/kernel/kernel.nix args)
    .linuxKernel_7_1_4_hardenedOverlay
    (import ./package/overlay/fwupd/fwupd-pcrlock.nix)

    self.inputs.nix-vscode-extensions.overlays.default
    self.inputs.nix-zed-extensions.overlays.default
    (import ./package/overlay/landstrip.nix)
    # oo7 content-type fix: patch the Secret Service daemon (oo7-server) to
    # stop rejecting spec-legal MIME content types, so clients like aws-vault
    # (which label secrets "application/json") can store them. Replaces the
    # older aws-vault-side relabel workaround. See package/overlay/oo7/json.nix.
    (import ./package/overlay/oo7/json.nix)
    # oo7 Secret-portal fix: patch the vendored ashpd in oo7-portal so a
    # digit-leading portal token no longer panics the RetrieveSecret handler,
    # which hung Chromium/Electron (Claude Desktop) on startup. Supersedes the
    # claude-desktop-side --disable-features=DbusSecretPortal workaround below
    # (patch/oo7.nix, now disabled). See package/overlay/oo7/portal-token.nix.
    (import ./package/overlay/oo7/portal-token.nix)
    # (import ./package/overlay/codex-acp.nix)

    # key-rack version bump: nixpkgs has 0.4.0, upstream is ahead (0.6.0,
    # unreleased tag). See package/overlay/key-rack.nix for details.
    (import ./package/overlay/key-rack.nix)

    # Official Anthropic Claude Desktop (repackaged .deb) + app.asar patches.
    (import ./package/overlay/claude-desktop/overlay.nix)
    # Disabled: superseded by the daemon-side fix in ../oo7/portal-token.nix.
    # This only masked the panic by turning Chromium's Secret-portal client off.
    # (import ./package/overlay/claude-desktop/patch/oo7.nix)
    (import ./package/overlay/claude-desktop/patch/debug-port-guard.nix)
    (import ./package/overlay/claude-desktop/patch/vm-path.nix)
    (import ./package/overlay/claude-desktop/patch/cli-path.nix)
    # (import ./package/overlay/claude-desktop/patch/3p/model-id-normalization.nix)
    # (import ./package/overlay/claude-desktop/patch/3p/thinking-flag.nix)
    # (import ./package/overlay/claude-desktop/patch/3p/titlegen-thinking.nix)
    # (import ./package/overlay/claude-desktop/patch/3p/chat-effort-toggle.nix)

  ];

  nix.settings.experimental-features = [
    "nix-command"
    "flakes"
  ];

  # Whitelist unfree packages
  # Define here instead of flake.nix to avoid replacing the whole pkgs
  nixpkgs.config.allowUnfreePredicate =
    pkg: builtins.elem (lib.getName pkg) allowedUnfree;

  # Project-local `/sandbox` choices override user settings. Managed settings
  # have higher precedence, keeping Claude's bubblewrap sandbox disabled in
  # favor of the Landstrip wrapper configured in home-manager.devbox.nix.
  environment.etc."claude-code/managed-settings.json".text = builtins.toJSON {
    sandbox.enabled = false;
  };

  # Replace stdenv with Clang/LLVM and compile with NixOS' hardening
  # This enables Clang-specific features (CFI) but disables GCC plugins (entropy, randstruct, structleak, and stackleak)
  boot.kernelPackages =
    pkgs.hardenedLinuxPackagesFor pkgs.linuxKernel.kernels.linux_7_1
      (old: {
        stdenv = pkgs.withCFlags [
          "-Wno-unused-command-line-argument"
        ] (import ./package/overlay/bintools.nix args).llvm;
        # stdenv = pkgs.withCFlags [ "-Wno-unused-command-line-argument" ] pkgs.llvmPackages.stdenv;

        extraMakeFlags = [ "LLVM=1" ]; # Use all LLVM bintools instead of just Clang
        ignoreConfigErrors = true; # Some GCC-specific hardening (e.g. GCC_PLUGINS) are set as non-optionally yes
      });

  # Kernel LSM support:
  # Exclusive LSM: NixOS doesn't really have a strong implementation: no SELinux, AppArmor has limited profile (due to non-FHS)
  # Stackable LSM: capability,landlock,yama,safesetid,bpf. No loadpin (fine since it's not embedded), lockdown, or integrity
  boot.kernelPatches = [
    {
      name = "patch";
      patch = null;
      structuredExtraConfig = with lib.kernel; {
        # Not to be confused with `structuedExtraConfig`, what a horrible naming scheme
        # Lockdown will deter firmware update on Chromebook
        SECURITY_LOCKDOWN_LSM = lib.mkForce yes; # Get kernel ready for lockdown mode

        MODULE_SIG = lib.mkForce yes; # Generate key, sign module, dump the private part
        # TODO: MODULE_SIG_FORCE?
        DEVMEM = lib.mkForce no; # /dev/mem: disable, not needed for 7040
        # Options for BIOS access for Chromebook
        # STRICT_DEVMEM = lib.mkForce yes;
        # IO_STRICT_DEVMEM = no;

        # Compiler
        LTO_CLANG_FULL = yes; # Enable full ClangLTO optimization (full). Note that since kCFI, this doesn't have any security benefit
      };
    }
  ];

  # Enabling LSM
  security.apparmor.enable = true;
  security.lsm = [ "lockdown" ];
  boot.kernelParams = [ "lockdown=confidentiality" ];

  # Hardened profile doesn't allow this?
  services.logrotate.checkConfig = false;
  security.rtkit.enable = true;

  # nix-ld: for packages that hasn't been nixified
  # e.g., `fw-ectool` and virtualhere
  programs.nix-ld.enable = true;
  # programs.nix-ld.libraries = with pkgs; [
  # 	libusb1			# For firmware updates with SuzyQ
  # ];

  # Enable cua-driver (also sets CUA_DRIVER_BIN)
  services.cua-driver = {
    enable = true;
    package = cua.packages.${pkgs.stdenv.hostPlatform.system}.cua-driver;
  };

  # Flatpak
  services.flatpak = {
    enable = true;
    uninstallUnmanaged = true;
    overrides.global = {
      Context.sockets = [
        # Wayland only
        "wayland"
        "!x11"
        "!fallback-x11"

        # Force apps to use xdg-dbus-proxy
        "!session-bus"
      ];
      # xdg-dbus-proxy session bus policy
      "Session Bus Policy" = {
        # Disable Secret Service to force usage of Secret Portal
        "org.freedesktop.secrets" = "none";
      };
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
