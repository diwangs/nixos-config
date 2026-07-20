{ config, ... }: {
  age.identityPaths = [
    "${config.home.homeDirectory}/.age-identity"
  ];

  /*
    landstrip sandbox policy for CLI agent bash tool

    This would also replace Claude Code's built-in bubblewrap sandbox which is
    based on bind-mounts and user namespaces instead of Landlock LSM, which
    has the following advantages:
    - Does not require creation of empty files or device nodes to satisfy
      bind-mount requirement. Claude Code is bad at cleaning up after itself.
    - Does not break programs that require non-character device nodes, such
      as `libgit2`.
    - Does not break programs that require non-symlink files, such as `zsh`
      dotfiles and `/run/wrappers`, which would hard-fail on bind.

    The cost of this is it requires Landlock LSM in the kernel, but it seems
    to be available on all machines that I use.
  */
  _module.args.landstripPolicyBase = {
    enabled = true;
    # Claude gets direct network access; OpenCode overrides this for its proxy.
    network = {
      # AF_UNIX
      allowAllUnixSockets = false;
      allowUnixSockets = [
        "/nix/var/nix/daemon-socket/socket" # nix build/eval
      ];
      # AF_INET: denied by default, re-deny if ancestor is allowed
      allowNetwork = false;
      allowLocalBinding = true; # dev servers may bind/connect loopback
      allowedDomains = [ "*" ];
      deniedDomains = [ ];
    };
    filesystem = {
      /*
        Best linux apps store their secrets with `libsecret` (GNOME Keyring)
        Good linux apps read secrets from env (hence the need of `agenix`)
        Okay linux apps store their secrets in top-level ~ (e.g., `~/.aws`)
        Bad linux apps store their secrets in XDG base dirs (e.g., OC /connect)
        This policy assumes we don't have bad apps!
      */

      # read: allowed by default, re-allow if ancestor is denied
      denyRead = [
        "/run/agenix.d" # decrypted agenix secrets (root)
        "/run/user/*/agenix.d" # decrypted agenix secrets (user)
        "/nix/secret" # age identity key (root)
        config.home.homeDirectory # age identity key (user), okay apps secrets

        "${config.xdg.configHome}/zsh/.zsh_history"

        "**/.env*" # .envrc is fine since we `cat` from agenix
      ];
      allowRead = [
        config.xdg.configHome
        config.xdg.dataHome
        config.xdg.stateHome
        config.xdg.cacheHome
        "${config.home.homeDirectory}/.profile" # For `bash` warning
        "${config.home.homeDirectory}/.bash_profile" # For `bash` warning
        "${config.home.homeDirectory}/.gitconfig" # For `libgit2`
        # Agent settings
        "${config.home.homeDirectory}/.claude/settings.json"
        "${config.home.homeDirectory}/.claude/settings.local.json"

        "."
      ];
      # write: denied by default, re-deny if ancestor is allowed
      allowWrite = [
        "/dev/null"
        "/tmp"

        config.xdg.configHome
        config.xdg.dataHome
        config.xdg.stateHome
        config.xdg.cacheHome

        "."
      ];
      denyWrite = [
        # Agent local settings (may disable sandbox next session)
        ".claude/settings.json"
        ".claude/settings.local.json"

        # rc-style script (except shell since they source from nix store)
        "**/.git/commondir" # CVE-2026-?
        "**/.envrc"
      ];
    };
  };
}
