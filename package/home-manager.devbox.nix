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
    awscli2
  ];

  # Dev
  programs.direnv = {
    enable = true; # Add direnv package and sets the shell hook
    nix-direnv.enable = true; # Cached nix-shell/nix develop environments
  };
  programs.gh.enable = true;

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
    extensions = [ "nix" ];
    userSettings = {
      # Feed each project's direnv (.envrc) into the environment Zed computes
      # for terminals, language servers, and external ACP agent servers.
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
  # NOTE: `settings` is intentionally left empty. home-manager writes
  # settings.json as a read-only /nix/store symlink, which makes Claude Code's
  # own runtime writes (e.g. adjusting the effort level) fail with EROFS. We
  # instead materialize a writable copy in the activation script below.
  programs.claude-code = {
    enable = true;
    settings = { };

    # Custom auto-deny classifier for the Bash tool: an additive hard-block layer
    # on top of landstrip (the OS enforcement floor) and the auto-mode classifier.
    # It inspects the ORIGINAL command (landstrip wrapping happens transparently
    # inside $CLAUDE_CODE_SHELL, so the command string Claude sees is untouched)
    # and denies known sandbox-escape / secret-exfil patterns. Fail-open by
    # design — any internal error falls through to exit 0, since landstrip still
    # contains whatever ultimately runs. Extend the pattern list as needed.
    hooks."claude-landstrip-deny" = ''
      #!${pkgs.runtimeShell}
      # Read the PreToolUse payload; bail out (allow) on any parsing trouble.
      input="$(cat)" || exit 0
      cmd="$(printf '%s' "$input" | ${pkgs.jq}/bin/jq -r '.tool_input.command // empty' 2>/dev/null)" || exit 0
      [ -n "$cmd" ] || exit 0

      deny() {
        ${pkgs.jq}/bin/jq -cn --arg r "$1" \
          '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"deny",permissionDecisionReason:$r}}' 2>/dev/null
        exit 0
      }
      m() { printf '%s' "$cmd" | ${pkgs.gnugrep}/bin/grep -Eiq -- "$1"; }

      # --- privilege escalation / sandbox tooling ---
      m '(^|[^[:alnum:]_])(sudo|doas|pkexec)([^[:alnum:]_]|$)' \
        && deny "privilege escalation (sudo/doas/pkexec) is blocked in the sandbox"
      m '(^|[^[:alnum:]_])(bwrap|bubblewrap|unshare)([^[:alnum:]_]|$)' \
        && deny "invoking namespace/sandbox tooling is blocked"
      m 'CLAUDE_CODE_SHELL' \
        && deny "tampering with CLAUDE_CODE_SHELL is blocked"

      # --- config / rc tampering (would alter the sandbox or shell on next run) ---
      m '\.claude/settings(\.local)?\.json' \
        && deny "editing Claude Code settings.json is blocked"
      m '>[[:space:]>]*([^[:space:];|&]*/)?\.(bashrc|bash_profile|profile|zshrc|zprofile|zshenv)([^[:alnum:]]|$)' \
        && deny "writing shell rc files is blocked"

      # --- network exfiltration heuristics (landstrip runs with open network) ---
      m '(curl|wget)[^|;&]*[|][[:space:]]*(sudo[[:space:]]+)?(ba)?sh([^[:alnum:]]|$)' \
        && deny "piping a network download into a shell is blocked"
      m '(id_ed25519|id_rsa|\.age-identity|/\.ssh/|/\.aws/|/\.gnupg/|credentials)[^|;&]*[|][^|]*(curl|wget|nc|ncat|netcat|socat|scp)' \
        && deny "piping secret material to the network is blocked"

      exit 0
    '';
  };

  # Copy settings.json into place as a real, writable file so Claude Code can
  # persist runtime changes (effort level, etc.). Runs unconditionally on
  # every switch and every boot, so any runtime edits are reset to these
  # declarative defaults on the next activation.
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
              to restrict sensitive directory under home.
            */
            landstripReadDenyGlobs = lib.concatMap toClaudeGlobs (
              builtins.filter (
                p: p != config.home.homeDirectory
              ) landstripPolicyBase.filesystem.denyRead
            );
            landstripWriteDenyGlobs = lib.concatMap toClaudeGlobs landstripPolicyBase.filesystem.denyWrite;

            homeSecretGlobs = [
              "~/*" # Direct children only

              "~/.aws/**"
              "~/.ssh/**"
              "~/.gnupg/**"
              "~/.claude/.credentials.json" # Claude Code OAuth token

              "~/Desktop/**"
              "~/Documents/**"
              "~/Downloads/**"
              "~/Music/**"
              "~/Pictures/**"
              "~/Videos/**"
            ];
          in
          {
            "$schema" = "https://json.schemastore.org/claude-code-settings.json";
            defaultMode = "auto";
            # tui = "default"; # Prevent spammy ctrl+g
            env = {
              CLAUDE_CODE_ENABLE_AUTO_MODE = "1";
              CLAUDE_CODE_SUBPROCESS_ENV_SCRUB = "0"; # Enables bwrap if true
              # Route Bash tool through landstrip, but keep ! unsandboxed
              SHELL = "${pkgs.bashInteractive}/bin/bash";
              CLAUDE_CODE_SHELL = "${pkgs.writeShellScriptBin "bash" ''
                exec ${lib.getExe pkgs.landstrip} -p ${
                  (pkgs.formats.json { }).generate "claude-landstrip-policy.json"
                    landstripPolicyBase
                } -- ${pkgs.bashInteractive}/bin/bash "$@"
              ''}/bin/bash";
              CLAUDE_BASH_NO_LOGIN = "1";
            };
            permissions.deny =
              (map (g: "Read(${g})") (landstripReadDenyGlobs ++ homeSecretGlobs))
              ++ (map (g: "Edit(${g})") (
                landstripReadDenyGlobs ++ landstripWriteDenyGlobs ++ homeSecretGlobs
              ))
              # Mirrors landstripPolicyBase's network policy for the Bash
              # tool (deniedDomains is currently empty, so this is a no-op
              # today but tracks future changes automatically). allowedDomains
              # and the allowNetwork bool are intentionally not derived:
              # Claude Code has no deny-all-except-these-domains primitive for
              # WebFetch, and allowNetwork's semantics relative to the domain
              # lists aren't documented anywhere in this repo or upstream.
              ++ (map (d: "WebFetch(domain:${d})") landstripPolicyBase.network.deniedDomains);
            sandbox.enabled = false;
            # Run the custom auto-deny classifier before every Bash command.
            # landstrip is the OS enforcement floor; this hard-blocks a few
            # escape/exfil patterns before the command ever reaches landstrip.
            hooks.PreToolUse = [
              {
                matcher = "Bash";
                hooks = [
                  {
                    type = "command";
                    command = "${config.programs.claude-code.configDir}/hooks/claude-landstrip-deny";
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
