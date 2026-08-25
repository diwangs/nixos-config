{
  config,
  pkgs,
  lib,
  ...
}:
rec {
  age.identityPaths = [
    "${config.home.homeDirectory}/.age-identity-pq"
  ];

  /*
    landstrip sandbox policy for CLI agent bash tool

    This replaces Claude Code's built-in bubblewrap sandbox and runs inside
    Codex's bubblewrap process sandbox. Landlock-based filesystem policy has
    the following advantages over bind-mount path masking:
    - Does not require creation of empty files or device nodes to satisfy
      bind-mount requirement. Claude Code is bad at cleaning up after itself.
    - Does not break programs that require non-character device nodes, such
      as `libgit2`.
    - Does not break programs that require non-symlink files, such as `zsh`
      dotfiles and `/run/wrappers`, which would hard-fail on bind.

    Codex's outer bubblewrap instance keeps its user/PID namespaces, fresh
    /proc, and process hardening. It exposes the host filesystem read-write so
    this Landstrip policy remains the sole path and socket policy.

    The cost of this is it requires Landlock LSM in the kernel, but it seems
    to be available on all machines that I use.

    The policy below is additive:
    - Does not protect directories already protected by UNIX permissions
    - Does not protect `/proc`, `/dev`, etc. Use `bwrap` for these
    - Does not protect environment variables. Use agent-specific mechanisms.

    The policy below is additive, i.e., it does not cover things that is
    already covered by UNIX permissions (e.g., root-owned files, nix store).
  */
  _module.args.landstripPolicyBase = {
    enabled = true;
    # Keep Internet sockets unrestricted while retaining path mediation for
    # AF_UNIX. Unlike allowNetwork, allowAllInetSockets does not bypass the
    # Unix-socket allowlist.
    network = {
      allowNetwork = false; # Disable master override
      # AF_UNIX
      allowAllUnixSockets = false;
      allowUnixSockets = [
        "/nix/var/nix/daemon-socket/socket" # nix build/eval
        "/run/user/${toString config.home.uid}/agent-browser/"
        "/tmp/" # Temporary UNIX sockets (e.g., Chrome)
      ];
      # AF_INET and AF_INET6, including TCP and UDP.
      allowAllInetSockets = true;
      allowLocalBinding = true;
    };
    filesystem = {
      /*
        Best linux apps store their secrets with portal (+ sandbox)
        Better linux apps store their secrets with service (oo7 secret service)
        Good linux apps read secrets from env (hence the need of `agenix`)
        Okay linux apps store their secrets in top-level ~ (e.g., `~/.aws`)
        Bad linux apps store their secrets in XDG base dirs (e.g., OC /connect)
        This policy assumes we don't have bad apps!
      */

      # read: allowed by default, re-allow if ancestor is denied
      denyRead = [
        "/run/user/${toString config.home.uid}/credentials" # systemd-creds
        "/run/user/${toString config.home.uid}/agenix.d" # agenix secrets

        config.home.homeDirectory # age identity key (user), okay apps secrets

        "${config.xdg.configHome}/zsh/.zsh_history"
        "${config.home.homeDirectory}/.codex/auth.json" # Devbox only
        "${config.home.homeDirectory}/.claude/.credentials.json"

        "**/.env*" # .envrc is fine since we `cat` from agenix
      ];
      allowRead = [
        "/" # Somehow this needs to be explicit?

        config.xdg.configHome
        config.xdg.dataHome
        config.xdg.stateHome
        config.xdg.cacheHome
        "${config.home.homeDirectory}/.profile" # For `bash` warning
        "${config.home.homeDirectory}/.bash_profile" # For `bash` warning
        "${config.home.homeDirectory}/.bashrc" # For `bash` warning
        "${config.home.homeDirectory}/.gitconfig" # For `libgit2`

        "${config.home.homeDirectory}/.codex"
        "${config.home.homeDirectory}/.claude"
        "${config.home.homeDirectory}/.npm"
        "${config.home.homeDirectory}/.bun"
        "${config.home.homeDirectory}/.codeql"
        "${config.home.homeDirectory}/.docker/buildx"

        "."
      ];

      # write: denied by default, re-deny if ancestor is allowed
      allowWrite = [
        "/dev/null"
        "/dev/shm"
        "/tmp"

        "/run/user/${toString config.home.uid}/agent-browser/"

        config.xdg.configHome
        config.xdg.dataHome
        config.xdg.stateHome
        config.xdg.cacheHome

        "${config.home.homeDirectory}/.codex"
        "${config.home.homeDirectory}/.claude"
        "${config.home.homeDirectory}/.npm"
        "${config.home.homeDirectory}/.bun"
        "${config.home.homeDirectory}/.codeql"
        "${config.home.homeDirectory}/.docker/buildx"

        "."
      ];
      denyWrite = [
        # Agent local settings (may disable sandbox next session)
        ".claude/settings.json"
        ".claude/settings.local.json"

        # rc-style script (except shell since they source from nix store)
        "**/.git/commondir" # CVE-2026-?
        # "**/.envrc"
      ];
    };
  };

  # Materialized policy shared by agent Bash-tool wrappers (Codex, Claude
  # Code). Generated here, next to the base policy, so it stays a single
  # unmodified file rather than something each consumer re-derives.
  _module.args.landstripPolicyFile =
    (pkgs.formats.json { }).generate "agent-landstrip-policy.json"
      _module.args.landstripPolicyBase;

  # Codex hook shared by the base and opt-in profiles. Keep it beside the
  # Landstrip policy inputs it wraps so consumers only provide the selected
  # materialized policy and presentation details.
  _module.args.mkCodexBashLandstripHook =
    {
      policyFile,
      scriptName,
      statusMessage,
    }:
    {
      matcher = "^Bash$";
      hooks = [
        {
          type = "command";
          command = "${pkgs.writeShellScript scriptName ''
            deny() {
              printf '%s\n' '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"landstrip wrap hook failed; refusing to run unsandboxed"}}'
              exit 0
            }

            result="$(${lib.getExe pkgs.jq} -c \
              --arg prefix ${lib.escapeShellArg "${
                # Use a policy file rather than Landstrip's policy-on-stdin mode so
                # wrapped commands (notably apply_patch) retain their original stdin.
                pkgs.writeShellScript "agent-landstrip-run" ''
                  if [ "$#" -eq 0 ]; then
                    printf '%s\n' "landstrip runner: missing command" >&2
                    exit 64
                  fi

                  exec ${lib.getExe pkgs.landstrip} run -p ${policyFile} -- \
                    ${lib.getExe pkgs.tini} -s -- "$@"
                ''
              } ${pkgs.bashInteractive}/bin/bash -c "} \
              'if (.tool_input | type) != "object" or (.tool_input.command | type) != "string" or .tool_input.command == "" then error("invalid Bash tool input") else .tool_input as $ti | { hookSpecificOutput: { hookEventName: "PreToolUse", permissionDecision: "allow", updatedInput: ($ti + { command: ($prefix + ($ti.command | @sh)) }) } } end' \
              2>/dev/null)" || deny
            [ -n "$result" ] || deny
            printf '%s\n' "$result"
          ''}";
          timeout = 10;
          inherit statusMessage;
        }
      ];
    };
}
