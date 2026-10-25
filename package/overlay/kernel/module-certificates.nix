# nixpkgs signs modules with per-module kmodigest certificates, which only
# `rebuildImage` embeds into the kernel. The plain image trusts none of them,
# so MODULE_SIG_FORCE rejects every module (incl. `nvme` in stage 1, hence no
# LUKS prompt). Point both `$out/kernel` and bootspec (read by lanzaboote) at
# the rebuilt image, as in nixpkgs' `nixos/tests/kernel-module-verification.nix`.
{
  lib,
  config,
  options,
  pkgs,
  ...
}:
{
  system.systemBuilderCommands =
    let
      inherit (config.boot.kernelPackages) kernel rebuildImage;
      signedKernel = rebuildImage {
        inherit (kernel) target;
        inherit (config.system) modulesTree;
      };
    in
    lib.mkAfter ''
      ln -sfn ${signedKernel}/${config.system.boot.loader.kernelFile} $out/kernel
    '';
  boot.bootspec.writer = ''
    ${options.boot.bootspec.writer.default}
    ${lib.getExe pkgs.buildPackages.jq} --sort-keys \
      --arg kernel "$(readlink $out/kernel)" \
      '."org.nixos.bootspec.v1".kernel = $kernel' \
      $out/${config.boot.bootspec.filename} > "$TMPDIR/boot.json"
    mv "$TMPDIR/boot.json" $out/${config.boot.bootspec.filename}
  '';
}
