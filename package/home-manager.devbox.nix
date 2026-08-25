# Home packages and programs shared between the laptop and rootless devboxes
# (imported by package/home-manager.nix and home-manager.devbox.nix).
# Keep this list headless: no desktop, dconf, Flatpak, or system-service
# assumptions — and no laptop-only specialArgs (`secrets`, `pkgs-stable`).
{
  config,
  pkgs,
  lib,
  landstripPolicyBase, # shared sandbox policy, defined in aspect/secret.hm.nix
  landstripPolicyFile, # landstripPolicyBase materialized to JSON, also from aspect/secret.hm.nix
  mkCodexBashLandstripHook, # shared hook builder, also from aspect/secret.hm.nix
  ...
}:
{
  home.packages = with pkgs; [
    # Runtime environment (or environment manager)
    fnm # Node.js version manager 					(`fnm exec --using=24`)
    # uv # Python environment manager       (`uv run`)
    docker-client # Docker CLI, to be used with Podman

    # DevEx
    nixd # Nix LSP for Zed and ACP agents
    tmux

    # Little tools
    jq # JSON parser
  ];

  # Dev
  programs.gh.enable = true;
  programs.direnv = {
    enable = true; # Add direnv package and sets the shell hook
    nix-direnv.enable = true; # Cached nix-shell/nix develop environments
  };
  programs.uv = {
    enable = true;
    settings = {
      python-downloads = "manual";
      python-preference = "only-managed";
    };
  };
  programs.bun = {
    enable = true;
    settings = {
      install = {
        globalStore = true; # pnpm-style global store
        linker = "isolated";
      };
    };
  };

  # Zed server
  programs.zed-editor = {
    enable = true;
    # Deliberately-empty package — only its `remote_server` passthru matters —
    # so the module's own installRemoteServer logic (package ? remote_server)
    # symlinks the matching server binary without installing the full GUI.
    package = pkgs.emptyDirectory.overrideAttrs (old: {
      passthru = (old.passthru or { }) // {
        inherit (pkgs.zed-editor) remote_server remoteServerExecutableName;
      };
    });
    installRemoteServer = true;
    mutableUserSettings = false;
    mutableUserKeymaps = false;
    userSettings = {
      load_direnv = "direct";
      # External agents speak ACP over stdio. Pin each executable to the Nix
      # store rather than relying on Zed's runtime-downloaded adapters.
      agent_servers = {
        "codex-acp" = {
          command = lib.getExe pkgs.codex-acp;
          env = {
            CODEX_PATH = lib.getExe pkgs.codex;
            INITIAL_AGENT_MODE = "agent-full-access";
            CODEX_CONFIG = builtins.toJSON {
              # codex-acp merges this into every new and resumed app-server
              # thread, where hook discovery and trust are evaluated.
              bypass_hook_trust = true;
            };
          };
        };
        "claude-code-acp" = {
          command = lib.getExe pkgs.claude-agent-acp;
          env.CLAUDE_CODE_EXECUTABLE = lib.getExe pkgs.claude-code;
        };
      };
      languages.Nix.language_servers = [
        "nixd"
        "!nil"
      ];
    };
  };

  # CLI agent: Codex
  programs.codex = {
    enable = true;
    # Run the declarative hooks without an interactive trust prompt and trust
    # the project from which the CLI is launched. ACP configures both concerns
    # per thread instead, so its CODEX_PATH points directly to pkgs.codex.
    package = pkgs.writeShellApplication {
      name = "codex";
      derivationArgs.version = lib.getVersion pkgs.codex;
      text = ''
        codex_project_toml="$(${lib.getExe pkgs.jq} -Rn --arg path "$PWD" '$path')"
        exec ${lib.getExe pkgs.codex} \
          --dangerously-bypass-hook-trust \
          -c "projects={$codex_project_toml={trust_level=\"trusted\"}}" \
          "$@"
      '';
    };
    settings = {
      cli_auth_credentials_store = lib.mkDefault "file"; # keyring in desktop
      allow_login_shell = false; # Preserve Codex tool shims in PATH
      shell_environment_policy = {
        ignore_default_excludes = true;
        filters = {
          "*KEY*" = "exclude";
          "*SECRET*" = "exclude";
          "*PASSWORD*" = "exclude";
          # No allow-in-deny, so spell out exclude rule for *TOKEN*
          AWS_BEARER_TOKEN_BEDROCK = "exclude";
        };
      };
      # Keep Codex's process sandbox while delegating filesystem and socket
      # policy to the Landstrip wrapper installed by the hooks below.
      default_permissions = "Profile-based";
      permissions."Profile-based" = {
        description = "Bubblewrap process isolation with Landstrip filesystem and socket policy based on selected profile.";
        # Reopen the ordinary FHS trees for Landstrip, along with explicit
        # metadata opt-outs that prevent Codex from creating synthetic mask
        # targets in system-owned directories. Excludes special fs directories
        # such as `/sys`, `/proc`, and `/dev`.
        filesystem =
          lib.genAttrs (lib.concatMap
            (
              root:
              [ root ]
              ++ map (name: "${root}/${name}") [
                ".git"
                ".agents"
                ".codex"
              ]
            )
            [
              "/boot"
              "/usr"
              "/var"
              "/etc"
              "/run"
              "/tmp"
              "/root"
              "/home"
            ]
          ) (_: "write")
          // {
            ":root" = "read";

            # `/dev` itself stays bwrap's minimal device tree. Reopen only the
            # host shared-memory mount, whose access is still mediated by
            # Landstrip. Explicit project metadata writes keep Landstrip, rather
            # than Codex's automatic workspace carveouts, authoritative there.
            "/dev/shm" = "write";
            ":workspace_roots" = {
              "." = "write";
              ".git" = "write";
              ".agents" = "write";
              ".codex" = "write";
            };
          };
        network.enabled = true;
      };
      approval_policy = "never"; # was "on-request"
      # approvals_reviewer = "auto_review";
      model = "gpt-5.6-sol";
      model_reasoning_effort = "medium";
      hooks.PreToolUse = [
        {
          matcher = "^apply_patch$";
          hooks = [
            {
              type = "command";
              command = "${pkgs.writeShellScript "codex-apply-patch-landstrip-block" ''
                printf '%s\n' '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"apply_patch tool disabled. Bypasses sandbox. Retry through bash tool. Accepts same patch as argument or stdin."}}'
              ''}";
              timeout = 10;
              statusMessage = "Routing patch through Landstrip";
            }
          ];
        }
        (mkCodexBashLandstripHook {
          policyFile = landstripPolicyFile;
          scriptName = "codex-bash-landstrip-wrap";
          statusMessage = "Entering Landstrip sandbox";
        })
      ];
    };
    context = ''
      # Sandbox
      - Bubblewrap provides user/PID namespaces and a fresh /proc
      - Landstrip restricts filesystem access and allowlists AF_UNIX socket paths
      - Landstrip leaves AF_INET and AF_INET6 sockets unrestricted

      # Python and Node in Nix Environment
      - Python is available via `uv` (e.g., `uv run`)
      - Node is available via `fnm` (e.g., `fnm exec --using=24`)
    '';
    profiles = rec {
      # Custom profile to use Bedrock.
      bedrock = {
        model_provider = "amazon-bedrock";
        model_providers.amazon-bedrock.aws.region = "us-east-1";
        model = "openai.gpt-5.6-sol"; # openai prefix
      };

      # Opt-in access to the Docker-compatible rootless Podman API.
      docker = {
        hooks = {
          # Hook state keys are positional. The base Bash matcher is the second
          # PreToolUse group, with its wrapper as the first handler.
          state."${config.home.homeDirectory}/.codex/config.toml:pre_tool_use:1:0".enabled =
            false;
          PreToolUse = [
            (mkCodexBashLandstripHook {
              # The Docker-compatible Podman API deliberately crosses the
              # Landstrip filesystem boundary: the rootless service runs
              # outside the agent sandbox with the user's authority. Keep this
              # exception opt-in and socket-specific.
              policyFile =
                (pkgs.formats.json { }).generate "agent-landstrip-docker-policy.json"
                  (
                    lib.recursiveUpdate landstripPolicyBase {
                      network.allowUnixSockets = landstripPolicyBase.network.allowUnixSockets ++ [
                        "/run/user/${toString config.home.uid}/podman/podman.sock"
                      ];
                    }
                  );
              scriptName = "codex-bash-landstrip-docker-wrap";
              statusMessage = "Entering Docker-capable Landstrip sandbox";
            })
          ];
        };
      };

      # Codex selects one profile at launch, so compose both deltas explicitly.
      bedrock-docker = lib.recursiveUpdate bedrock docker;
    };
  };

  # CLI agent: Claude Code
  programs.claude-code = {
    enable = true;
    settings = { }; # Defined below to make it writable
  };

  home.activation.claudeSettings = lib.hm.dag.entryAfter [ "linkGeneration" ] ''
    		dst="$HOME/.claude/settings.json"
    		run rm -f "$dst"
    		run install -Dm600 ${
        (pkgs.formats.json { }).generate "claude-code-settings.json" (
          let
            # Landstrip to Claude Code policy translation
            toClaudeGlobs =
              path:
              let
                anchored = if lib.hasPrefix "/" path then "/${path}" else path;
              in
              [
                anchored
                "${anchored}/**"
              ];

            /*
              Special handling for home directory

              Landstrip policy is specificity-centric. Claude Code policy
              is flat deny -> ask -> allow path. Landstrip's home policy can't
              be applied directly to Claude Code. We therefore turn the home
              directory from deny to allow, and create a new explicit denylist
              to restrict sensitive directory (okay and bad apps) under home.
            */
            landstripReadDenyGlobs = lib.concatMap toClaudeGlobs (
              builtins.filter (
                p: p != config.home.homeDirectory
              ) landstripPolicyBase.filesystem.denyRead
            );
            runtimeAgenixReadDenyGlobs = toClaudeGlobs "/run/user/*/agenix.d";
            landstripWriteDenyGlobs = lib.concatMap toClaudeGlobs landstripPolicyBase.filesystem.denyWrite;

            homeSecretGlobs = [
              "~/.age-identity" # Direct children dotfiles
              "~/.aws/**"
              "~/.ssh/**"
              "~/.gnupg/**"

              "~/Desktop/**"
              "~/Documents/**"
              "~/Downloads/**"
              "~/Music/**"
              "~/Pictures/**"
              "~/Videos/**"
            ];

            # Read-only: readable (not in Read deny), but not directly editable.
            homeReadOnlyGlobs = [
              "~/.claude/settings.json"
              "~/.claude/settings.local.json"
            ];
          in
          {
            "$schema" = "https://json.schemastore.org/claude-code-settings.json";
            defaultMode = "auto";
            tui = "fullscreen";
            sandbox.enabled = false;
            autoMemoryEnabled = false;
            context = ''
              @~/.codex/AGENTS.md
            '';
            env = {
              CLAUDE_CODE_ENABLE_AUTO_MODE = "1";
              CLAUDE_CODE_SUBPROCESS_ENV_SCRUB = "0"; # Enables bwrap if true
              CLAUDE_CODE_SHELL = "${pkgs.writeShellScriptBin "bash" ''
                unset $(${pkgs.coreutils}/bin/env | ${pkgs.coreutils}/bin/cut -d= -f1 | ${pkgs.gnugrep}/bin/grep -Ei '(KEY|SECRET|PASSWORD|^AWS_BEARER_TOKEN_BEDROCK$)')
                exec ${pkgs.bashInteractive}/bin/bash "$@"
              ''}/bin/bash";
              CLAUDE_BASH_NO_LOGIN = "1";
            };
            permissions.deny =
              (map (g: "Read(${g})") (
                landstripReadDenyGlobs ++ runtimeAgenixReadDenyGlobs ++ homeSecretGlobs
              ))
              ++ (map (g: "Edit(${g})") (
                landstripReadDenyGlobs
                ++ runtimeAgenixReadDenyGlobs
                ++ landstripWriteDenyGlobs
                ++ homeSecretGlobs
                ++ homeReadOnlyGlobs
              ));

            # Use landstrip for Bash tool but not for ! shell-mode. Any rewrite
            # error denies the call rather than running it unsandboxed.
            # Note: per-command nesting means a model `cd`/`export` does not
            # persist across tool calls (chain within a single command instead)
            hooks.PreToolUse = [
              {
                matcher = "Bash";
                hooks = [
                  {
                    type = "command";
                    command = "${pkgs.writeShellScript "claude-bash-landstrip-wrap" ''
                      result="$(${lib.getExe pkgs.jq} -c --arg prefix ${lib.escapeShellArg "${
                        # Use a policy file rather than Landstrip's policy-on-stdin mode so
                        # wrapped commands (notably apply_patch) retain their original stdin.
                        pkgs.writeShellScript "agent-landstrip-run" ''
                          if [ "$#" -eq 0 ]; then
                            printf '%s\n' "landstrip runner: missing command" >&2
                            exit 64
                          fi

                          exec ${lib.getExe pkgs.landstrip} run -p ${landstripPolicyFile} -- \
                            ${lib.getExe pkgs.tini} -s -- "$@"
                        ''
                      } ${pkgs.bashInteractive}/bin/bash -c "} '.tool_input as $ti | ($ti.command // "") as $c | if $c == "" then empty else { hookSpecificOutput: { hookEventName: "PreToolUse", updatedInput: ($ti + { command: ($prefix + ($c | @sh)) }) } } end' 2>/dev/null)" || {
                        printf '%s' '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"landstrip wrap hook failed; refusing to run unsandboxed"}}'
                        exit 0
                      }
                      [ -n "$result" ] && printf '%s' "$result"
                      exit 0
                    ''}";
                  }
                ];
              }
            ];
          }
        )
      } "$dst"
     	'';

  # CLI Agent: OpenCode
  # Deprecated; kept for reference, not deleted. (Line-commented rather than
  # /* */ because embedded globs like "/run/user/*/agenix/**" contain a
  # literal `*/` that would close a block comment early.)
  # programs.opencode = {
  #   enable = true;
  #   extraPackages = [ pkgs.nixd ];
  #   settings = {
  #     autoupdate = false;
  #     lsp = true;
  #     plugin = [ "opencode-landstrip" ];
  #     permission = {
  #       "*" = "allow";
  #       # Mirrors the bash sandbox below (xdg.configFile "opencode/sandbox.json"):
  #       # deny the whole home directory by default and re-allow only the same
  #       # few safe subtrees, rather than a short blocklist of specific secret
  #       # dirs. External paths (this is the only place they're gated: it's
  #       # checked, with the absolute path, before and independently of
  #       # `read`/`edit` — whose own patterns are worktree-relative and never
  #       # observe an absolute path at all).
  #       #
  #       # Granularity note: every query here is "immediate children of some
  #       # directory D", and a configured pattern's `*`/`**` both expand to the
  #       # same unbounded regex wildcard (no single- vs. multi-segment
  #       # distinction) — so, unlike the bash sandbox, a lone top-level dotfile
  #       # can't be carved out of the deny without reopening all of home's top
  #       # level to listing. The bash sandbox's `~/.gitconfig` exception is
  #       # therefore intentionally dropped here: it stays denied.
  #       external_directory = {
  #         "*" = "allow";
  #         "~/**" = "deny";
  #         "~/.config/**" = "allow";
  #         "~/.local/share/**" = "allow";
  #         "~/.local/share/opencode/**" = "deny"; # antipattern: secrets in `share`
  #         "~/.cache/**" = "allow";
  #         "/nix/secret/**" = "deny"; # agenix host key
  #         "/run/agenix/**" = "deny"; # decrypted agenix secrets (nixos module)
  #         "/run/user/*/agenix/**" = "deny"; # decrypted agenix secrets (home-manager module)
  #       };
  #     };
  #   };
  #   tui.plugin = [ "opencode-landstrip/tui" ];
  # };
  #
  # # Config for bash tool landstrip sandbox. Derived from the shared base policy
  # # in aspect/secret.hm.nix (single source of truth) with OpenCode's deltas:
  # # direct network is denied by default (the opencode-landstrip plugin runs an
  # # in-process proxy for per-domain filtering) and unix sockets are restricted to
  # # the nix daemon; it also protects its own config + auth token from writes.
  # # The list orderings below are chosen to keep the emitted JSON byte-equivalent
  # # to the previous inline definition.
  # #
  # # NOTE: at this current version, there is a bypass intended to make session-
  # # level exception by doing the syscall twice. Re-check in the future if there
  # # is a more user-dependent authorization flow.
  # xdg.configFile."opencode/sandbox.json".text = builtins.toJSON (
  #   lib.recursiveUpdate landstripPolicyBase {
  #     network.allowNetwork = false; # plugin proxy handles per-domain filtering
  #     network.allowAllUnixSockets = false;
  #     filesystem.denyRead = landstripPolicyBase.filesystem.denyRead ++ [
  #       "~/.local/share/opencode/auth.json" # antipattern: secrets in `share`
  #     ];
  #     filesystem.denyWrite = [
  #       "~/.config/opencode/sandbox.json"
  #       ".opencode/sandbox.json"
  #     ]
  #     ++ landstripPolicyBase.filesystem.denyWrite;
  #   }
  # );
}
