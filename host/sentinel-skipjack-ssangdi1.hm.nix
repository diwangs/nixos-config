# JHU ARCH Skipjack (rootless HPC). No /nix on the cluster: the store lives on
# group scratch and is bind-mounted at /nix by nix-user-chroot. Compute-node
# SSH logins enter it automatically through a forced command (nix-enter), so
# Zed's remote server, terminals and agents all run inside /nix.
# Bootstrap and laptop-side SSH: see host/skipjack/README.md.
{
  config,
  lib,
  pkgs,
  ...
}:
let
  home = config.home.homeDirectory;
  bin = "${home}/.local/bin";

  # Canonical path behind ~/scratch_ycao43 (WekaFS, shared with the group).
  nixRoot = "/scratch/jhu/ycao43/ssangdi1/.nix";

  # Runs outside /nix, so it must be static. Only this crate builds locally
  # (seconds); the musl Rust toolchain comes from the binary cache.
  nixUserChroot = "${pkgs.pkgsStatic.nix-user-chroot}/bin/nix-user-chroot";

  nixEnter = pkgs.replaceVars ./skipjack/nix-enter.sh {
    inherit nixRoot;
    chrootBin = "${bin}/nix-user-chroot";
  };

  # Key logins to compute nodes always land in /nix. (The login node only
  # accepts MFA, so this never applies there.)
  authorizedKeys = pkgs.writeText "skipjack-authorized-keys" ''
    command="${bin}/nix-enter" ${(import ./identity/ssh.nix).diwangsPiv} diwangs-piv
  '';
in
{
  home.stateVersion = "25.05";
  home.username = "ssangdi1";
  home.uid = 11498;
  home.homeDirectory = "/home/jhu/ssangdi1"; # explicit, since it's under `jhu`

  # Non-NixOS Linux hosts need profile/session glue that NixOS
  # normally provides.
  targets.genericLinux.enable = true;
  xdg.enable = true;
  manual.manpages.enable = true;

  # nix.conf for the single-user store. GC keeps it from crowding the
  # group's scratch quota.
  nix = {
    package = pkgs.nix;
    settings = {
      experimental-features = [
        "nix-command"
        "flakes"
      ];
      auto-optimise-store = true;
      min-free = 10 * 1024 * 1024 * 1024;
      max-free = 40 * 1024 * 1024 * 1024;
    };
  };

  # sshd and the login node read these outside /nix, so they must be real
  # files, not store symlinks. Write to a temporary file, then rename, so
  # running copies (e.g. nix-user-chroot) aren't truncated.
  home.activation.skipjackGlue = lib.hm.dag.entryAfter [ "linkGeneration" ] ''
    skipjackPut() {
      install -Dm"$1" "$2" "$3.tmp"
      mv -f "$3.tmp" "$3"
    }
    run skipjackPut 755 ${nixUserChroot} ${bin}/nix-user-chroot
    run skipjackPut 755 ${nixEnter} ${bin}/nix-enter
    run skipjackPut 755 ${./skipjack/jump.sh} ${bin}/skipjack-jump
    run skipjackPut 755 ${./skipjack/stop.sh} ${bin}/skipjack-stop
    run install -dm700 ${home}/.ssh
    run skipjackPut 600 ${authorizedKeys} ${home}/.ssh/authorized_keys
  '';

  home.sessionPath = [ "$HOME/.local/bin" ];

  # No secrets on this shared cluster: agenix stays off, so the private
  # os-secret input is never fetched here (no agent needed to switch).
  age.enable = false;

  # No Secret Service on this rootless host
  programs.codex.settings.cli_auth_credentials_store = "file";
}
