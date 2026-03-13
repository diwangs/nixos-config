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
  
  # Alpha quality
  linuxKernel_6_18_13_hardenedOverlay = (final: prev: {
    linuxKernel = prev.linuxKernel // {
      kernelPatches = prev.linuxKernel.kernelPatches // {
        hardened = prev.linuxKernel.kernelPatches.hardened // {
          "6.18" = {
            version = "6.18.13";
            extra = "";	# nbouchinet's 6.18 patch doesn't set EXTRAVERSION=-hardened1; this keeps `uname` the same
            sha256 = "0zv8qml075jpk2i58cxp61hm3yb74mpkbkjg15n87riqzmakqb7d";		# Hash of the pre-patch kernel
            name = "linux-hardened-6.18.13-hardened1";
            patch = final.fetchurl {
              name = "linux-hardened-v6.18.13-hardened1.patch";
              url = "https://github.com/nbouchinet-anssi/linux-hardened/releases/download/v6.18.13-hardened1/linux-hardened-v6.18.13-hardened1.patch";
              sha256 = "10k33gf24ayaxk02zfkdn6cyrhgfl5q8iim3fkfkxq7n56zkdw3j";	# Hash of the patch itself
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