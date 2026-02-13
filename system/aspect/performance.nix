{ config, lib, pkgs, ... }: {
  # Don't use performance-minded custom kernel / patchset (e.g. Zen, TKG, Xanmod) because
  # 1. Already used a patchset (Hardened) and introducing another is a complication
  # 2. Traditionally significant performance enhancement comes from new hardware and algorithm / module (e.g. MGLRU) anyway 
  #     rather than a patchset (see [Phoronix 2023 benchmark](https://www.phoronix.com/review/arch-linux-kernels-2023)).
  #     If an enhancement is so good, they're probably in the work of upstreaming anyway (or optional feature).

  # Kernel config: add via `kernelPatches` instead of `structuredExtraConfig` because `hardenedKernelFor` would replace them
  # Add -O3, ClangLTO, and Polly
	boot.kernelPatches = [{
		name = "performance-patch";
		patch = null;
		structuredExtraConfig = with lib.kernel; {	# Not to be confused with `structuedExtraConfig`, what a horrible naming scheme
      # Compiler
			LTO_CLANG_FULL = yes;			# Enable full ClangLTO optimization (full). Note that since kCFI, this doesn't have any security benefit
		};
	}];

  # Network -> Google BBRv3 TCP CC algorithm
  # MGLRU: enabled by default
}