# =====================
# LLVM Toolchain Stdenv
# =====================
# 
# This is like `clangStdenv`, but includes the whole LLVM toolchain (e.g., lld).
# This is done by modifying the `stdenv` (specifically its C compiler) to use 
# the desired bintools by inheriting it.
# 
# NOTE: pre 6.13, an additional workaround is needed by null-ing the bintools's 
# `sharedLibraryLoader` to trick Nix to use a non-nixified loader like lld.
# https://github.com/NixOS/nixpkgs/issues/242244#issuecomment-1694235345
# 
# TODO: instead of doing this, try overriding buildPackages? Like linux_5_4

{ config, lib, pkgs, ... } : {
  # LLVM 21.1.2, fails due to missing __kcfi_typeid_clear_page_rep symbol?
	llvm = pkgs.overrideCC pkgs.llvmPackages.stdenv (
		pkgs.llvmPackages.stdenv.cc.override {
			inherit (pkgs.llvmPackages) bintools;
		}
	);

	# LLVM 20.1.6: one version behind, works as of 6.17.11
	llvm20 = pkgs.overrideCC pkgs.llvmPackages_20.stdenv (
		pkgs.llvmPackages_20.stdenv.cc.override {
			inherit (pkgs.llvmPackages_20) bintools;
		}
	);
}