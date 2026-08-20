{ ... }:
{
  services.userborn.enable = true;

  users = {
    mutableUsers = false;
    allowNoPasswordLogin = true; # Use FIDO2 exclusively
    users = {
      # Mark root account as locked
      root.hashedPassword = "!";

      # All machines share the same username
      diwangs = {
        isNormalUser = true;
        uid = 1000; # Stable runtime directory for the desktop SSH agent.
        # Pay attention to `nullok` in services still using `pam_unix`.
        hashedPassword = "*"; # Account is not locked but password is disabled
        extraGroups = [
          "wheel" # For ‘sudo’ and `iwd`.
          "networkmanager"
          "dialout" # Serial connection
          "adbusers" # Android debugging
          "plugdev" # HackRF
        ];
        # Subordinate id ranges for user namespaces, needed by rootless podman.
        # `userborn` itself does write /etc/sub{u,g}id, but nixpkgs' userborn
        # module builds its own users JSON that drops these ranges (only the
        # legacy perl path forwards them), so userborn sees no subid config and
        # just rewrites whatever it already read. The files below are therefore
        # the real source of content -- keep the two in sync.
        subUidRanges = [
          {
            startUid = 100000;
            count = 65536;
          }
        ];
        subGidRanges = [
          {
            startGid = 100000;
            count = 65536;
          }
        ];
      };
    };
  };

  # Materialize `/etc/subuid` and `/etc/subgid`: the nixpkgs `userborn` module
  # never forwards the ranges above to userborn, so nothing else populates them.
  # One line per range, "name:start:count"; mirrors the sole user's ranges above.
  #
  # TODO: Delete this whole block once the `nixpkgs` FlakeHub pin includes
  # NixOS/nixpkgs#508608 ("nixos/userborn: manage /etc/sub{u,g}id", merged to
  # master 2026-08-20, after our 2026-08-16 pin). That PR maps the ranges above
  # into userborn's own schema (`autoSubIdRange`, `{ start, count }`), so
  # userborn populates both files and `subUidRanges`/`subGidRanges` become the
  # single source of truth. Check with:
  #   nix eval --raw .#nixosConfigurations.paladin-iii.config \
  #     .systemd.services.userborn.serviceConfig.ExecStart   # -> userborn.json
  #   jq '.users[] | select(.name == "diwangs")' <that json>  # subUidRanges yet?
  # Removing it is not optional once the pin moves: with `mutableUsers = false`
  # the updated module bind-mounts /etc/sub{u,g}id read-only in ExecStartPost,
  # which `environment.etc` cannot then replace with its symlink at activation.
  environment.etc = {
    subuid = {
      text = "diwangs:100000:65536\n";
      mode = "0644";
    };
    subgid = {
      text = "diwangs:100000:65536\n";
      mode = "0644";
    };
  };
}
