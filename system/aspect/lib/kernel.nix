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

# Last updated: 260310
{ config, pkgs, lib, ... }: {
  
  # Latest stable from anthraxx
  linuxKernel_6_19_7_hardenedOverlay = (final: prev: {
    linuxKernel = prev.linuxKernel // {
      kernelPatches = prev.linuxKernel.kernelPatches // {
        hardened = prev.linuxKernel.kernelPatches.hardened // {
          "6.19" = {
            version = "6.19.7";
            extra = "-hardened1";
            sha256 = "0blmc3gmqyg1fj390gjz3brjznyn7s9m4f6w107ypygmhf5qgh82";		# Hash of the pre-patch kernel
            name = "linux-hardened-6.19.7-hardened1";
            patch = final.fetchurl {
              name = "linux-hardened-v6.19.7-hardened1.patch";
              url = "https://github.com/anthraxx/linux-hardened/releases/download/v6.19.7-hardened1/linux-hardened-v6.19.7-hardened1.patch";
              sha256 = "1k080qxcj9nid54wxb0lcgziq3lalgb1m9j59iv9cbqv4ixkwn37";	# Hash of the patch itself
            };
          };
        };
      };
    };
  });

  # Backup: Latest LTS
  linuxKernel_6_18_16_hardenedOverlay = (final: prev: {
    linuxKernel = prev.linuxKernel // {
      kernelPatches = prev.linuxKernel.kernelPatches // {
        hardened = prev.linuxKernel.kernelPatches.hardened // {
          "6.18" = {
            version = "6.18.16";
            extra = "-hardened1";
            sha256 = "1qwfsbr315c6qh3hnqmyjwjcj0h8j3w56hbrxnrx3h849lgw08ag";		# Hash of the pre-patch kernel
            name = "linux-hardened-6.18.16-hardened1";
            patch = final.fetchurl {
              name = "linux-hardened-v6.18.16-hardened1.patch";
              url = "https://github.com/anthraxx/linux-hardened/releases/download/v6.18.16-hardened1/linux-hardened-v6.18.16-hardened1.patch";
              sha256 = "174a228s7v0vdq0klndvfkpbv3v485s3kq5anmwm8z617a460516";	# Hash of the patch itself
            };
          };
        };
      };
    };
  });
}