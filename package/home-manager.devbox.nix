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
              to restrict sensitive directory (okay and bad apps) under home.
            */
            landstripReadDenyGlobs = lib.concatMap toClaudeGlobs (
              builtins.filter (
                p: p != config.home.homeDirectory
              ) landstripPolicyBase.filesystem.denyRead
            );
            landstripWriteDenyGlobs = lib.concatMap toClaudeGlobs landstripPolicyBase.filesystem.denyWrite;

            homeSecretGlobs = [
              "~/*" # Direct children files
              "~/.*" # Direct children dotfiles

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
            env = {
              CLAUDE_CODE_ENABLE_AUTO_MODE = "1";
              CLAUDE_CODE_SUBPROCESS_ENV_SCRUB = "0"; # Enables bwrap if true
              # Route Bash tool through landstrip, but keep ! unsandboxed
              # NOTE: Landstrip has a --trap-fd mechanism to allow session
              # level exception. For now this is disabled entirely.
              SHELL = "${pkgs.bashInteractive}/bin/bash";
              CLAUDE_CODE_SHELL = "${pkgs.writeShellScriptBin "bash" ''
                unset $(compgen -A export | ${pkgs.gnugrep}/bin/grep -Ei '(TOKEN|SECRET|API_KEY|PASSWORD)')
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
                landstripReadDenyGlobs
                ++ landstripWriteDenyGlobs
                ++ homeSecretGlobs
                ++ homeReadOnlyGlobs
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
