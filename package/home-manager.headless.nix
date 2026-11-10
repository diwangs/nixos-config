# Home packages and programs shared between the laptop and rootless devboxes,
# imported by home-manager.headless.nix (which home-manager.nix layers
# package/home-manager.nix on top of).
# Keep this list headless: no desktop, dconf, Flatpak, or system-service
# assumptions — and no laptop-only specialArgs (`secrets`, `pkgs-stable`).
{
  config,
  pkgs,
  lib,
  landstripPolicyBase, # shared sandbox policy, defined in aspect/secret.hm.nix
  landstripPolicyFile, # landstripPolicyBase materialized to JSON, also from aspect/secret.hm.nix
  mkAgentBashLandstripHook, # shared hook builder, also from aspect/secret.hm.nix
  ...
}:
let
  # Shared opt-in policy for both agents. The rootless Podman service runs
  # outside Landstrip with the user's authority; allow only its specific socket.
  dockerLandstripPolicyFile =
    (pkgs.formats.json { }).generate "agent-landstrip-docker-policy.json"
      (
        lib.recursiveUpdate landstripPolicyBase {
          network.allowUnixSockets = landstripPolicyBase.network.allowUnixSockets ++ [
            "/run/user/${toString config.home.uid}/podman/podman.sock"
          ];
        }
      );

  claudeProfiles = rec {
    docker.env.AGENT_SANDBOX_PROFILE = "docker";
    # Use Mantle with the caller's AWS credential chain (including aws-vault), without
    # putting credentials in the Nix store or changing the normal Claude login.
    bedrock.env = {
      # Disable Invoke API routing even if inherited from the shell or user settings.
      CLAUDE_CODE_USE_BEDROCK = "0";
      CLAUDE_CODE_USE_MANTLE = "1";
      AWS_REGION = "us-east-1";
    };
    bedrock-docker = lib.recursiveUpdate bedrock docker;
  };
  claudeProfileFiles = lib.mapAttrs (
    name: settings:
    (pkgs.formats.json { }).generate "claude-${name}-settings.json" settings
  ) claudeProfiles;

  claudeBashHookCommands =
    lib.mapAttrs
      (
        name: policyFile:
        (builtins.head
          (mkAgentBashLandstripHook {
            inherit policyFile;
            scriptName = "claude-bash-landstrip-${name}-wrap";
            statusMessage = "Entering Bubblewrap and Landstrip sandbox";
          }).hooks
        ).command
      )
      {
        default = landstripPolicyFile;
        docker = dockerLandstripPolicyFile;
      };
in
{
  home.packages = with pkgs; [
    # Runtime environment (or environment manager)
    # TODO: change `fnm` to `viteplus` when available to have similar workflow with `uv`
    fnm # Node.js version manager 					(`fnm exec --using=24`)
    # uv # Python environment manager       (`uv run`)
    docker-client # Docker CLI, to be used with Podman
    minikube

    # DevEx
    nixd # Nix LSP for Zed and ACP agents
    tmux

    # Little tools
    jq # JSON parser
    aws-vault # STS credential broker through ECS servers
    yubikey-manager # Supplies aws-vault's built-in non-terminal ykman driver
  ];

  # AWS CLI and aws-vault; role profiles need the host's agenix declaration.
  # Usage: aws-vault exec --ecs-server <profile> -- codex
  # With the file backend, omit --lazy to unlock the cache before Codex starts.
  # ykman is only invoked when an MFA token is requested.
  programs.awscli = {
    enable = true;
    settings =
      lib.optionalAttrs (builtins.hasAttr "token/access-nova.json" config.age.secrets)
        {
          "profile nova" = {
            credential_process = "${pkgs.coreutils}/bin/cat /run/user/${toString config.home.uid}/agenix/token/access-nova.json";
          };
          "profile mantle" = {
            source_profile = "nova";
            role_arn = "arn:aws:iam::995133654082:role/diwangs-mantle";
            region = "us-east-1";
          };
          "profile mantle-tf" = {
            source_profile = "nova";
            role_arn = "arn:aws:iam::995133654082:role/diwangs-mantle-tf";
            region = "us-east-2";
          };
          "profile mantle-eks" = {
            source_profile = "nova";
            role_arn = "arn:aws:iam::995133654082:role/diwangs-mantle-eks";
            region = "us-east-2";
          };
        };
  };

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
          type = "custom";
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
          type = "custom";
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

  # CLI Editor: neovim (default $EDITOR; the desktop overrides it with Zed)
  home.sessionVariables.EDITOR = lib.mkDefault "nvim";
  programs.neovim = {
    enable = true;

    # New defaults
    withPython3 = false;
    withRuby = false;
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
    # The ChatGPT desktop app persists its UI state (e.g., the Chat/Codex tab) to
    # `[desktop]` in config.toml and rolls the change back if the write fails.
    mutableSettings = true;
    settings = {
      cli_auth_credentials_store = lib.mkDefault "keyring"; # oo7 Secret Service
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
      # Bash hooks enforce Bubblewrap and Landstrip independently of Codex's
      # sandbox mode, including full access. Native apply_patch is blocked below.
      sandbox_mode = "danger-full-access";
      approval_policy = "never"; # was "on-request"
      # approvals_reviewer = "auto_review";
      model = "gpt-6.1-sol";
      model_reasoning_effort = "medium";
      tui.status_line = [
        "model-with-reasoning"
        "current-dir"
        "context-used"
        "five-hour-limit"
      ];
      hooks.PreToolUse = [
        {
          matcher = "^apply_patch$";
          hooks = [
            {
              type = "command";
              command = "${pkgs.writeShellScript "codex-apply-patch-landstrip-block" ''
                printf '%s\n' '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"Tool disabled, bypasses sandbox. Retry through Bash, has sandbox hook."}}'
              ''}";
              timeout = 10;
              statusMessage = "Routing patch through Landstrip";
            }
          ];
        }
        (mkAgentBashLandstripHook {
          policyFile = landstripPolicyFile;
          scriptName = "codex-bash-landstrip-wrap";
          statusMessage = "Entering Bubblewrap and Landstrip sandbox";
        })
      ];
    };
    context = ''
      # Sandbox
      - Bash hooks provide Bubblewrap user/PID/IPC namespaces, minimal /dev, and fresh /proc, including in full access mode
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
        model = "openai.gpt-6.1-sol"; # openai prefix
      };

      # Opt-in access to the Docker-compatible rootless Podman API.
      docker = {
        hooks = {
          # Hook state keys are positional. The base Bash matcher is the second
          # PreToolUse group, with its wrapper as the first handler.
          state."${config.home.homeDirectory}/.codex/config.toml:pre_tool_use:1:0".enabled =
            false;
          PreToolUse = [
            (mkAgentBashLandstripHook {
              policyFile = dockerLandstripPolicyFile;
              scriptName = "codex-bash-landstrip-docker-wrap";
              statusMessage = "Entering Docker-capable Bubblewrap and Landstrip sandbox";
            })
          ];
        };
      };

      # Codex selects one profile at launch, so compose both deltas explicitly.
      bedrock-docker = lib.recursiveUpdate bedrock docker;
    };
  };

  # Same merge as upstream's codexMutableSettings, applied to each profile file:
  # declared values win, keys Codex writes (e.g., `[desktop]`) are preserved.
  home.activation.codexMutableProfiles =
    lib.mkIf
      (config.programs.codex.mutableSettings && config.programs.codex.profiles != { })
      (
        lib.hm.dag.entryAfter [ "linkGeneration" ] (
          lib.concatStringsSep "\n" (
            lib.mapAttrsToList (
              name: settings:
              lib.hm.generators.mkImpureConfigMerger {
                inherit pkgs;
                format = "toml";
                empty = "{}";
                jqOperation = "$dynamic * $static";
                path = "${config.home.homeDirectory}/.codex/${name}.config.toml";
                staticSettings =
                  (pkgs.formats.toml { }).generate "codex-${name}-config"
                    settings;
                mode = "600";
              }
            ) config.programs.codex.profiles
          )
        )
      );

  # CLI agent: Claude Code
  programs.claude-code = {
    enable = true;
    # Merge into a writable settings.json so changes Claude Code persists (e.g.,
    # via /config) survive activation. Declared values below take precedence.
    mutableSettings = true;
    settings = {
      permissions.defaultMode = "bypassPermissions";
      skipDangerousModePermissionPrompt = true;
      tui = "fullscreen";
      sandbox.enabled = false;
      autoMemoryEnabled = false;
      context = ''
        @~/.codex/AGENTS.md
        Only Bash, Agent, TaskStop, ToolSearch, AskUserQuestion, and ExitPlanMode
        are permitted. Use shell commands for reading, searching, editing, and
        other operations; all other tools are blocked.
      '';
      env = {
        CLAUDE_CODE_SUBPROCESS_ENV_SCRUB = "0"; # Enables bwrap if true
        CLAUDE_CODE_SHELL = "${pkgs.writeShellScriptBin "bash" ''
          unset $(${pkgs.coreutils}/bin/env | ${pkgs.coreutils}/bin/cut -d= -f1 | ${pkgs.gnugrep}/bin/grep -Ei '(KEY|SECRET|PASSWORD|^AWS_BEARER_TOKEN_BEDROCK$)')
          exec ${pkgs.bashInteractive}/bin/bash "$@"
        ''}/bin/bash";
        CLAUDE_BASH_NO_LOGIN = "1";
      };

      # Deny every other tool except AskUserQuestion and ExitPlanMode (no side
      # effects outside the sandbox), TaskStop (only stops background tasks),
      # ToolSearch (only loads tool schemas; loaded tools still hit this hook) and
      # Agent (subagent tool calls pass through this same hook), including MCP
      # and newly introduced tools. ArtifactComments only exchanges text. Skill
      # only loads instructions (forked skills run as subagents, hooked as above).
      # Artifact and ArtifactData are allowed unless they read local files
      # (`file_path`) into a shared database or write downloads to an arbitrary
      # local path (`out_dir`); both would bypass the Landstrip policy.
      # PreToolUse decisions also apply in bypassPermissions mode.
      hooks.PreToolUse = [
        {
          matcher = "*";
          hooks = [
            {
              type = "command";
              command = "${pkgs.writeShellScript "claude-non-bash-block" ''
                if ${lib.getExe pkgs.jq} -e '
                  (.tool_name | IN("Bash", "Agent", "TaskStop", "ToolSearch", "AskUserQuestion", "ExitPlanMode", "ArtifactComments", "Skill"))
                  or (.tool_name == "Artifact" and (.tool_input | has("out_dir") | not))
                  or (.tool_name == "ArtifactData" and (.tool_input | (has("out_dir") or has("file_path") or any(.writes[]?; has("file_path"))) | not))
                ' >/dev/null 2>&1; then
                  exit 0
                fi
                printf '%s\n' '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"Tool disabled, bypasses sandbox or includes `out_dir` or `file_path`. Strip them or retry through Bash, has sandbox hook."}}'
              ''}";
              timeout = 10;
            }
          ];
        }
        # Tool calls are wrapped; interactive ! shell-mode is outside this hook.
        # Nesting means cd/export do not persist between tool calls.
        {
          matcher = "^Bash$";
          hooks = [
            {
              type = "command";
              # Hook lists merge across settings sources. Dispatch here so
              # exactly one wrapper rewrites each Bash command, even when
              # --settings selects an opt-in profile.
              command = "${pkgs.writeShellScript "claude-bash-landstrip-wrap" ''
                case "''${AGENT_SANDBOX_PROFILE:-default}" in
                  default) exec ${claudeBashHookCommands.default} ;;
                  docker) exec ${claudeBashHookCommands.docker} ;;
                  *)
                    printf '%s\n' 'Unknown AGENT_SANDBOX_PROFILE; refusing to run unsandboxed' >&2
                    exit 2
                    ;;
                esac
              ''}";
              timeout = 10;
              statusMessage = "Entering Bubblewrap and Landstrip sandbox";
            }
          ];
        }
      ];
    };
  };

  # Select a profile at launch: claude --settings ~/.claude/profiles/docker.json
  home.file =
    lib.mapAttrs' (
      name: source:
      lib.nameValuePair ".claude/profiles/${name}.json" {
        inherit source;
      }
    ) claudeProfileFiles
    # Upstream links Codex profiles read-only from the store even with
    # mutableSettings, so `codex --profile <name>` cannot persist its writes.
    # Unlink them here; codexMutableProfiles merges them into writable files.
    // lib.optionalAttrs config.programs.codex.mutableSettings (
      lib.mapAttrs' (
        name: _: lib.nameValuePair ".codex/${name}.config.toml" { enable = false; }
      ) config.programs.codex.profiles
    );
}
