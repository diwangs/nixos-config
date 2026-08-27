# ======================
#	linux-stable Hardening
# ======================
# Provide an overlay because NixOS' hardened patches lagged behind anthraxx's tree
# To update, check version from anthraxx's tree and NixOS `linux_latest` kernel in `nixpkgs/pkgs/top-level/linux-kernels.nix`
#
# moddir error will come up if NixOS hasn't supported a version yet
# See: https://github.com/NixOS/nixpkgs/blob/master/pkgs/os-specific/linux/kernel/kernels-org.json
#
# Important links
# kernel packages: https://github.com/NixOS/nixpkgs/tree/master/pkgs/os-specific/linux/kernel
# package group: https://github.com/NixOS/nixpkgs/blob/master/pkgs/top-level/linux-kernels.nix
#
# nix-prefetch-url mirror://kernel/linux/kernel/v6.x/linux-6.x.x.tar.xz
#
# NOTE: overlay `pkgs.linuxKernel.kernelPatches`, not `pkgs.kernelPatches`
#
# hardenedLinuxPackagesFor was removed from nixpkgs in commit 2879caafcf3fe36048fe25f99f32b91002128ca6
# along with kernelPatches.hardened and pkgs/os-specific/linux/kernel/hardened/config.nix.
# We re-implement them here so the overlay remains self-contained.

# Last updated: 240826
{ ... }:

let
  # Inlined from nixpkgs pkgs/os-specific/linux/kernel/hardened/config.nix
  # Removed in nixpkgs commit 2879caafcf3fe36048fe25f99f32b91002128ca6
  # Based on https://kspp.github.io/Recommended_Settings and https://wiki.gentoo.org/wiki/Hardened/Hardened_Kernel_Project
  hardenedConfig =
    {
      stdenv,
      lib,
      version,
    }:
    with lib.kernel;
    with (lib.kernel.whenHelpers version);
    assert (lib.versionAtLeast version "4.9");
    {
      SECURITY_SELINUX_DISABLE = whenOlder "6.4" no;
      SECURITY_WRITABLE_HOOKS = whenOlder "6.4" no;

      DEBUG_CREDENTIALS = whenOlder "6.6" yes;
      DEBUG_NOTIFIERS = yes;
      DEBUG_PI_LIST = whenOlder "5.2" yes;
      DEBUG_PLIST = whenAtLeast "5.2" yes;
      DEBUG_SG = yes;
      DEBUG_VIRTUAL = yes;
      SCHED_STACK_END_CHECK = yes;

      REFCOUNT_FULL = whenOlder "5.4.208" yes;
      RESET_ATTACK_MITIGATION = yes;
      CONFIG_LDISC_AUTOLOAD = option no;

      PAGE_POISONING_NO_SANITY = whenOlder "5.11" yes;
      PAGE_POISONING_ZERO = whenOlder "5.11" yes;
      INIT_ON_FREE_DEFAULT_ON = whenAtLeast "5.3" yes;
      INIT_STACK_ALL_ZERO = yes;
      ZERO_CALL_USED_REGS = whenAtLeast "5.15" yes;

      SECURITY_SAFESETID = whenAtLeast "5.1" yes;
      PANIC_TIMEOUT = freeform "-1";

      GCC_PLUGINS = yes;
      GCC_PLUGIN_STACKLEAK = whenAtLeast "4.20" yes;
      GCC_PLUGIN_RANDSTRUCT = whenOlder "5.19" yes;
      GCC_PLUGIN_RANDSTRUCT_PERFORMANCE = whenOlder "5.19" yes;

      UBSAN = yes;
      UBSAN_TRAP = whenAtLeast "5.7" yes;
      UBSAN_BOUNDS = whenAtLeast "5.7" yes;
      UBSAN_SANITIZE_ALL = whenOlder "6.9" yes;
      UBSAN_LOCAL_BOUNDS = option yes;
      # CFI_CLANG was renamed to the compiler-agnostic CFI in Linux 6.18
      # (transitional shim aside, the live symbol on >=6.18 is CONFIG_CFI).
      CFI_CLANG = whenOlder "6.18" (option yes);
      CFI = whenAtLeast "6.18" (option yes);

      ACPI_CUSTOM_METHOD = whenOlder "6.9" no;
      PROC_KCORE = no;
      INET_DIAG = no;
      INET_DIAG_DESTROY = option no;
      INET_RAW_DIAG = option no;
      INET_TCP_DIAG = option no;
      INET_UDP_DIAG = option no;
      INET_MPTCP_DIAG = option no;

      CC_STACKPROTECTOR_REGULAR = lib.mkForce (whenOlder "4.18" no);
      CC_STACKPROTECTOR_STRONG = whenOlder "4.18" yes;

      STRICT_DEVMEM = option no;
      IO_STRICT_DEVMEM = option no;

      IOMMU_DEFAULT_DMA_STRICT = option yes;
      IOMMU_DEFAULT_DMA_LAZY = option no;

      LEGACY_VSYSCALL_NONE = lib.mkIf stdenv.hostPlatform.isx86 yes;
    };

  # Re-implementation of linuxKernel.hardenedKernelFor, removed alongside hardenedLinuxPackagesFor
  makeHardenedKernelFor =
    {
      fetchurl,
      linuxKernel,
      lib,
    }:
    kernel': overrides:
    let
      kernel = kernel'.override overrides;
      patch = linuxKernel.kernelPatches.hardened.${kernel.meta.branch};
      version = patch.version;
      major = lib.versions.major version;
      # The kernel's module directory uses the full 3-component release, so a
      # ".0" line like 7.1 builds as 7.1.0. Pad here to match what the kernel
      # Makefile reports (else: "modDirVersion ... is wrong, should be 7.1.0-...").
      modDirVersion' = lib.versions.pad 3 version;
    in
    kernel.override {
      structuredExtraConfig = hardenedConfig {
        stdenv = kernel.stdenv;
        inherit lib version;
      };
      argsOverride = {
        inherit version;
        pname = "linux-hardened";
        modDirVersion = modDirVersion' + patch.extra;
        src = fetchurl {
          url = "mirror://kernel/linux/kernel/v${major}.x/linux-${version}.tar.xz";
          sha256 = patch.sha256;
        };
        extraMeta = {
          broken = kernel.meta.broken;
        };
      };
      kernelPatches = kernel.kernelPatches ++ [ patch ];
      isHardened = true;
    };

in
{

  # Pinned before Linux 7.2: that release can hang indefinitely during
  # shutdown/restart while tearing down Thunderbolt DisplayPort tunnels.
  # Before updating, verify the domain-reference-leak fix is included:
  # https://lore.kernel.org/r/20260823-b4-tbt-fixes-v2-3-26a18a426c9f@kernel.org
  # Regression: https://github.com/torvalds/linux/commit/f5cc545f59699549adbaa4084149f8247865a51d
  linuxKernel_7_1_9_hardenedOverlay = (
    final: prev: {
      linuxKernel = prev.linuxKernel // {
        kernelPatches = prev.linuxKernel.kernelPatches // {
          hardened = (prev.linuxKernel.kernelPatches.hardened or { }) // {
            "7.1" = {
              version = "7.1.9";
              extra = "-hardened1";
              sha256 = "1c3jq2y2isas3hi8dla4qs0wl6z6p9shjaqgk1987cwp72pa8w9j"; # Hash of the pre-patch kernel
              name = "linux-hardened-7.1.9-hardened1";
              patch = final.fetchurl {
                name = "linux-hardened-v7.1.9-hardened1.patch";
                url = "https://github.com/anthraxx/linux-hardened/releases/download/v7.1.9-hardened1/linux-hardened-v7.1.9-hardened1.patch";
                sha256 = "0jv0aj3qkys1hhw1ibjf1bcwxckv20jf7mwkpym5i2q2gy37a66h"; # Hash of the patch itself
              };
            };
          };
        };

        hardenedKernelFor = makeHardenedKernelFor {
          inherit (final) fetchurl;
          linuxKernel = final.linuxKernel;
          lib = prev.lib;
        };
        hardenedPackagesFor =
          kernel: overrides:
          final.linuxKernel.packagesFor (
            final.linuxKernel.hardenedKernelFor kernel overrides
          );
      };

      # Re-export matching the old pkgs.hardenedLinuxPackagesFor alias
      hardenedLinuxPackagesFor = final.linuxKernel.hardenedPackagesFor;
    }
  );

  # Backup: Latest LTS (6.x)
  linuxKernel_6_18_45_hardenedOverlay = (
    final: prev: {
      linuxKernel = prev.linuxKernel // {
        kernelPatches = prev.linuxKernel.kernelPatches // {
          hardened = (prev.linuxKernel.kernelPatches.hardened or { }) // {
            "6.18" = {
              version = "6.18.45";
              extra = "-hardened1";
              sha256 = "0cxbvrb43mqxjmxyz2i7n5xghrk4gx7n24js2an199lwaxb4myih"; # Hash of the pre-patch kernel
              name = "linux-hardened-6.18.45-hardened1";
              patch = final.fetchurl {
                name = "linux-hardened-v6.18.45-hardened1.patch";
                url = "https://github.com/anthraxx/linux-hardened/releases/download/v6.18.45-hardened1/linux-hardened-v6.18.45-hardened1.patch";
                sha256 = "198gzx70qw3nqwrwh1yiwcrg8plplc93lzzxc7gqzdkmgvqx0vxq"; # Hash of the patch itself
              };
            };
          };
        };

        hardenedKernelFor = makeHardenedKernelFor {
          inherit (final) fetchurl;
          linuxKernel = final.linuxKernel;
          lib = prev.lib;
        };
        hardenedPackagesFor =
          kernel: overrides:
          final.linuxKernel.packagesFor (
            final.linuxKernel.hardenedKernelFor kernel overrides
          );
      };

      hardenedLinuxPackagesFor = final.linuxKernel.hardenedPackagesFor;
    }
  );
}
