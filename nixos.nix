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
    .linuxKernel_7_1_9_hardenedOverlay
    (import ./package/overlay/fwupd/fwupd-pcrlock.nix)

    self.inputs.nix-vscode-extensions.overlays.default
    self.inputs.nix-zed-extensions.overlays.default
    (import ./package/overlay/landstrip/overlay.nix)
    # oo7 → git main. Both the content-type reject (aws-vault "application/json")
    # and the digit-leading portal-token panic (hung Claude Desktop on startup)
    # are now fixed upstream, so we build oo7 from a pinned main commit rather
    # than hand-patching. Replaces the former oo7/json.nix + oo7/portal-token.nix
    # overlays and supersedes the claude-desktop-side DbusSecretPortal workaround
    # below (patch/oo7.nix, still disabled). See package/overlay/oo7.nix.
    (import ./package/overlay/oo7.nix)
    (import ./package/overlay/codex-acp/overlay.nix)
    # Patches for YubiKey 5.7
    (import ./package/overlay/yubikey-agent.nix)
    (import ./package/overlay/age-plugin-yubikey/overlay.nix)

    (import ./package/overlay/key-rack/overlay.nix)

    # Dogfood the Linux packaging from nixpkgs PR #551713 as `pkgs.chatgpt`.
    # Vendored files are synced by package/overlay/chatgpt-draft/pull.sh.
    (import ./package/overlay/chatgpt-draft/overlay.nix)

    # Claude Desktop (repackaged .deb) + app.asar patches. Dogfooding the
    # upstream nixpkgs draft packaging (PR #537215) as the real `claude-desktop`:
    # it is vendored + pulled by package/overlay/claude-desktop-draft/pull.sh.
    # The local base overlay below is DISABLED (kept on disk) in favor of it.
    # (import ./package/overlay/claude-desktop/overlay.nix)
    (import ./package/overlay/claude-desktop-draft/overlay.nix)
    # The base patch/* overlays below target the top-level app.asar, which the
    # draft's FHS wrapping moves into passthru.unwrapped — so they'd break the
    # build and must be migrated per-patch. Disabled pending migration:
    #   - debug-port-guard: MIGRATED, see the draft patch imported below.
    #   - vm-path: redundant (the draft bakes the OVMF/virtiofsd asar rewrite
    #     into passthru.unwrapped's postFixup already).
    #   - cli-path: MIGRATED, see the draft patch imported below.
    # (import ./package/overlay/claude-desktop/patch/oo7.nix)
    # (import ./package/overlay/claude-desktop/patch/debug-port-guard.nix)
    # (import ./package/overlay/claude-desktop/patch/vm-path.nix)
    # (import ./package/overlay/claude-desktop/patch/cli-path.nix)
    (import ./package/overlay/claude-desktop-draft/patch/debug-port-guard.nix)
    (import ./package/overlay/claude-desktop-draft/patch/cli-path.nix)
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
        MODULE_SIG_FORCE = lib.mkForce yes;
        DEVMEM = lib.mkForce no; # /dev/mem: disable, not needed for 7040
        # Options for BIOS access for Chromebook
        # STRICT_DEVMEM = lib.mkForce yes;
        # IO_STRICT_DEVMEM = no;

        # Compiler
        LTO_CLANG_FULL = yes; # NOTE: since kCFI, this is only for performance
        # NOTE: as on 7.1.5, this breaks `bpf-restrict-fs`
      };
    }
  ];

  # Enabling LSM
  security.apparmor.enable = true;
  security.lsm = [ "lockdown" ];
  # Confidentiality broke `bpf` due to `bpf_probe_read_kernel`
  boot.kernelParams = [ "lockdown=integrity" ];

  # Hardened profile doesn't allow this?
  services.logrotate.checkConfig = false;
  security.rtkit.enable = true;

  # nix-ld: for packages that hasn't been nixified
  # e.g., `uv`-managed Python, `fnm`-managed Node
  programs.nix-ld.enable = true;
  # programs.nix-ld.libraries = with pkgs; [
  # 	libusb1			# For firmware updates with SuzyQ
  # ];
  # environment.localBinInPath = true; # Include `~/.local/bin` e.g., for `uv`

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
