# Home packages and programs shared between the laptop and rootless devboxes
# (imported by package/home-manager.nix and home-manager.devbox.nix).
# Keep this list headless: no desktop, dconf, Flatpak, or system-service
# assumptions — and no laptop-only specialArgs (`secrets`, `pkgs-stable`).
{
  config,
  pkgs,
  lib,
  landstripPolicyBase, # shared sandbox policy, defined in aspect/secret.hm.nix
  ...
}:
{
  home.packages = with pkgs; [
    # Runtime environment (or environment manager)
    fnm # Node.js version manager 					(eval $(fnm env))
    uv # Python environment manager

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
    userSettings = {
      load_direnv = "direct";
      # External agents speak ACP over stdio. Pin each executable to the Nix
      # store rather than relying on Zed's runtime-downloaded adapters.
      agent_servers = {
        "codex-acp" = {
          command = lib.getExe pkgs.codex-acp;
          env.CODEX_PATH = lib.getExe pkgs.codex;
        };
        "claude-code-acp" = {
          command = lib.getExe pkgs.claude-agent-acp;
          env.CLAUDE_CODE_EXECUTABLE = lib.getExe pkgs.claude-code;
        };
        "opencode" = {
          command = lib.getExe pkgs.opencode;
          args = [ "acp" ];
          env.OPENCODE_EXPERIMENTAL_LSP_TOOL = "true";
        };
      };
      languages.Nix.language_servers = [
        "nixd"
        "!nil"
      ];
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
            # Materialized landstrip policy, embedded into the Bash-tool
            # wrapping hook below (see hooks.PreToolUse).
            landstripPolicyFile =
              (pkgs.formats.json { }).generate "claude-landstrip-policy.json"
                landstripPolicyBase;

            # The static policy cannot name $XDG_RUNTIME_DIR portably. Add the
            # current user's agenix directory immediately before sandboxing,
            # rather than using Landstrip's eagerly-expanded /run/user/* glob.
            landstripRunner = pkgs.writeShellScript "claude-bash-landstrip-run" ''
              runtimeAgenixDir="/run/user/$(${pkgs.coreutils}/bin/id -u)/agenix.d"
              policy="$(${lib.getExe pkgs.jq} -c --arg runtimeAgenixDir "$runtimeAgenixDir" \
                '.filesystem.denyRead += [$runtimeAgenixDir]' \
                ${landstripPolicyFile})" || exit 1
              [ -n "$policy" ] || exit 1
              printf '%s\n' "$policy" | exec ${lib.getExe pkgs.landstrip} -- \
                ${pkgs.bashInteractive}/bin/bash -c "$1"
            '';

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
            env = {
              CLAUDE_CODE_ENABLE_AUTO_MODE = "1";
              CLAUDE_CODE_SUBPROCESS_ENV_SCRUB = "0"; # Enables bwrap if true
              CLAUDE_CODE_SHELL = "${pkgs.writeShellScriptBin "bash" ''
                unset $(${pkgs.coreutils}/bin/env | ${pkgs.coreutils}/bin/cut -d= -f1 | ${pkgs.gnugrep}/bin/grep -Ei '(TOKEN|SECRET|KEY|PASSWORD)')
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
                      result="$(${lib.getExe pkgs.jq} -c --arg prefix ${lib.escapeShellArg "${landstripRunner} "} '.tool_input as $ti | ($ti.command // "") as $c | if $c == "" then empty else { hookSpecificOutput: { hookEventName: "PreToolUse", updatedInput: ($ti + { command: ($prefix + ($c | @sh)) }) } } end' 2>/dev/null)" || {
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
  programs.opencode = {
    enable = true;
    extraPackages = [ pkgs.nixd ];
    settings = {
      autoupdate = false;
      lsp = true;
      plugin = [ "opencode-landstrip" ];
      permission = {
        "*" = "allow";
        # Mirrors the bash sandbox below (xdg.configFile "opencode/sandbox.json"):
        # deny the whole home directory by default and re-allow only the same
        # few safe subtrees, rather than a short blocklist of specific secret
        # dirs. External paths (this is the only place they're gated: it's
        # checked, with the absolute path, before and independently of
        # `read`/`edit` — whose own patterns are worktree-relative and never
        # observe an absolute path at all).
        #
        # Granularity note: every query here is "immediate children of some
        # directory D", and a configured pattern's `*`/`**` both expand to the
        # same unbounded regex wildcard (no single- vs. multi-segment
        # distinction) — so, unlike the bash sandbox, a lone top-level dotfile
        # can't be carved out of the deny without reopening all of home's top
        # level to listing. The bash sandbox's `~/.gitconfig` exception is
        # therefore intentionally dropped here: it stays denied.
        external_directory = {
          "*" = "allow";
          "~/**" = "deny";
          "~/.config/**" = "allow";
          "~/.local/share/**" = "allow";
          "~/.local/share/opencode/**" = "deny"; # antipattern: secrets in `share`
          "~/.cache/**" = "allow";
          "/nix/secret/**" = "deny"; # agenix host key
          "/run/agenix/**" = "deny"; # decrypted agenix secrets (nixos module)
          "/run/user/*/agenix/**" = "deny"; # decrypted agenix secrets (home-manager module)
        };
      };
    };
    tui.plugin = [ "opencode-landstrip/tui" ];
  };

  # Config for bash tool landstrip sandbox. Derived from the shared base policy
  # in aspect/secret.hm.nix (single source of truth) with OpenCode's deltas:
  # direct network is denied by default (the opencode-landstrip plugin runs an
  # in-process proxy for per-domain filtering) and unix sockets are restricted to
  # the nix daemon; it also protects its own config + auth token from writes.
  # The list orderings below are chosen to keep the emitted JSON byte-equivalent
  # to the previous inline definition.
  #
  # NOTE: at this current version, there is a bypass intended to make session-
  # level exception by doing the syscall twice. Re-check in the future if there
  # is a more user-dependent authorization flow.
  xdg.configFile."opencode/sandbox.json".text = builtins.toJSON (
    lib.recursiveUpdate landstripPolicyBase {
      network.allowNetwork = false; # plugin proxy handles per-domain filtering
      network.allowAllUnixSockets = false;
      filesystem.denyRead = landstripPolicyBase.filesystem.denyRead ++ [
        "~/.local/share/opencode/auth.json" # antipattern: secrets in `share`
      ];
      filesystem.denyWrite = [
        "~/.config/opencode/sandbox.json"
        ".opencode/sandbox.json"
      ]
      ++ landstripPolicyBase.filesystem.denyWrite;
    }
  );

  # CLI agent: Codex
  programs.codex = {
    enable = true;
    settings = { }; # Intentionally empty to allow mutability (e.g., dir trust)
  };

  # Copy config.toml into place as a real, writable file so Codex can persist
  # runtime changes (trusted directories, etc.). Runs unconditionally on every
  # switch and every boot, so any runtime edits are reset to these declarative
  # defaults on the next activation.
  home.activation.codexSettings = lib.hm.dag.entryAfter [ "linkGeneration" ] ''
    		dst="$HOME/.codex/config.toml"
    		run rm -f "$dst"
    		run install -Dm600 ${
        (pkgs.formats.toml { }).generate "codex-config.toml" {
          model_provider = "amazon-bedrock";
          model_providers."amazon-bedrock".aws.region = "us-east-1";
          approval_policy = "on-request";
          approvals_reviewer = "auto_review";
          model = "openai.gpt-5.6-terra";
          model_reasoning_effort = "xhigh";
        }
      } "$dst"
    	'';
}
