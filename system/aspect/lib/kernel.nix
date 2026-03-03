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

# Last updated: 250727
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

  linuxKernel_6_17_11_hardenedOverlay = (final: prev: {
    linuxKernel = prev.linuxKernel // {
      kernelPatches = prev.linuxKernel.kernelPatches // {
        hardened = prev.linuxKernel.kernelPatches.hardened // {
          "6.17" = {
            version = "6.17.11";
            extra = "-hardened1";
            sha256 = "0zi5mw6953iic9hwx78bjww81mcpb9y2sj5dgf819w9506pihjwk";		# Hash of the pre-patch kernel
            name = "linux-hardened-6.17.11-hardened1";
            patch = final.fetchurl {
              name = "linux-hardened-v6.17.11-hardened1.patch";
              url = "https://github.com/anthraxx/linux-hardened/releases/download/v6.17.11-hardened1/linux-hardened-v6.17.11-hardened1.patch";
              sha256 = "1ayg4k8g33zljvl71xq491hk8rx2rp5ssbdknjqqfz4ap82csyn3";	# Hash of the patch itself
            };
          };
        };
      };
    };
  });
}