# ======================
#	Thunderbolt DP tunnel shutdown hang
# ======================
# Linux 7.2 made nhi_pci_remove() wait for tb_domain_release(), but the async DP
# tunnel activation path leaks a domain reference when a DPRX read is canceled
# or still pending while the domain is stopped. Poweroff/reboot then hangs
# forever with a USB4/Thunderbolt display or dock attached.
#
# Regression: https://github.com/torvalds/linux/commit/f5cc545f59699549adbaa4084149f8247865a51d
# Fix: Sven Peter's series, merged for v7.3-rc3 (Cc: stable)
# https://lore.kernel.org/r/20260823-b4-tbt-fixes-v2-3-26a18a426c9f@kernel.org
#
# Applies cleanly (no fuzz) on top of 7.2.7 + linux-hardened 7.2.7-hardened1;
# the hardened patch touches nothing under drivers/thunderbolt.
#
# Remove this file once the series lands in a 7.2.x stable release (the
# patches will then fail to apply). Checked absent through 7.2.8.
{
  lib,
  fetchpatch,
  kernel,
}:

let
  commits = [
    {
      name = "thunderbolt-hold-router-ref-per-hopid";
      rev = "032c59c7681c661b63123231824170c025afb7e7";
      hash = "sha256-Sjw0hbXw2EBV7upqgMwr7hOJ18OajHMThytxEAFEPtU=";
    }
    {
      name = "thunderbolt-dp-activation-callback-mandatory";
      rev = "12f5d8b85a66a0ac08d082517d92ce136f8c0d42";
      hash = "sha256-ExtTS8ZsRPHH7YMJcyGPfmfC5epx2pPS7Ty55GDbiU8=";
    }
    {
      name = "thunderbolt-fix-domain-ref-leak-dprx-cancel";
      rev = "1fd1f67c94d30889377bba774f032ec15e8b9299";
      hash = "sha256-109fiESrzYGYpcCT+Xp7Q9WwIWOr4odhZr4VwVm9Qfc=";
    }
    {
      name = "thunderbolt-no-dp-tunnel-access-after-dprx-cancel";
      rev = "419fa32fa5bc2d7fb9d0d15d5630b1c1090808b3";
      hash = "sha256-dW3AcSLAphVi4e0RV+Pgt9pRB/dQu66UTPJPGMqbrPU=";
    }
    {
      name = "thunderbolt-mark-discovered-tunnels-active";
      rev = "c222f80be55f6c17851af1c68a70ae4046c848e2";
      hash = "sha256-dRLoH7EBDITf9+wI/iLcvHoVW4VpNRNIu/UlYk08qoY=";
    }
    {
      name = "thunderbolt-tear-down-inactive-dp-tunnels-on-stop";
      rev = "0b457c6733f73421a3fb03786f13d67c618b5119";
      hash = "sha256-VeA+3WtVo/2FTSaAyeAVCpTnvja2y8JKpeAlOuA3ces=";
    }
  ];
in
# Only 7.2.x carries the regression without the fix
lib.optionals (lib.versions.majorMinor kernel.version == "7.2") (
  map (c: {
    inherit (c) name;
    patch = fetchpatch {
      name = "${c.name}.patch";
      url = "https://github.com/torvalds/linux/commit/${c.rev}.patch";
      inherit (c) hash;
    };
  }) commits
)
