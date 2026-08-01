# Home packages are user packages that lacks integrated synchronization
# mechanism. User packages that have one (usually account-based), is
# preferred to use flatpak instead. To achieve reproducibility, its data is
# snapshoted.
#
# Example of home packages: vscodium, starship, zsh, obs
# Example of flatpak packages: steam, brave browser
#
# Few advantages of this approach:
# 1. Doesn't snapshot some authentication token
# 2. This kind of packages are usually closed-source, so we avoid unfree
# 		packages in Nix
#
# While this approach is not perfectly reproducible in hash sense
# it is reproducible in the synchronization sense, since the data are
# snapshoted

{
  lib,
  pkgs,
  pkgs-stable,
  ...
}:
{
  imports = [
    # Shared with rootless devboxes (fnm/uv/jq, direnv, gh, Claude Code, Codex)
    # TODO: change `fnm` to `viteplus` when available to have similar workflow with `uv`
    ./home-manager.devbox.nix
  ];

  home.packages =
    with pkgs;
    [
      # System
      lm_sensors # Power and temperature monitoring
      crosspipe # Pipewire multimedia patchbay
      key-rack

      # Runtime environment (or environment manager)
      conda # Python environment manager	  		(conda-shell)
      ansible
      sshpass
      ansible-lint
      aws-vault # STS credential broker through ECS servers

      # Agentic
      claude-desktop
      # cua-driver: installed system-wide via services.cua-driver (nixos.nix)
      # github-copilot-cli 		# Agentic LLM in the CLI

      # Media
      vlc

      # Peripherals
      yubioath-flutter # Yubikey reader
      trezor-suite # Trezor wallet (since no WebUSB in Firefox)
      ledger-live-desktop
      wsjtx # FT8 and WSPR
      flrig # Radio remote control (part of fldigi)
      # sdrangel					# SDR, failed on current version of flake?
      # mbelib						# sdrangel: decode AMBe (e.g., C4FM, D-STAR, DMR)
    ]
    ++ [
      pkgs-stable.codeql # Pin CodeQL. Also prevents download from vscode plugin
      # Small script to launch VSCode from Claude Code CLI
      (pkgs.writeShellScriptBin "code-wait" ''
        			exec ${pkgs.vscode}/bin/code --wait "$@" \
        				2> >(grep -v "is not in the list of known options, but still passed to Electron/Chromium" >&2)
        		'')
    ];

  # Dev (OpenCode, direnv, and gh live in home-manager.devbox.nix)
  programs.java = {
    # Aside from installing jdk (latest LTS), this sets JAVA_HOME
    enable = true;
    package = pkgs.jdk25; # Latest LTS
  };

  programs.git = {
    enable = true;
    lfs.enable = true;
  };

  # AWS CLI and `aws-vault`
  # Usage:
  # `aws-vault exec --ecs-server --lazy <profile> -- codex`
  home.sessionVariables.AWS_VAULT_SECRET_SERVICE_COLLECTION_NAME = "login";
  programs.awscli = {
    enable = true;
    settings = {
      "profile nova" = {
        credential_process = "/run/current-system/sw/bin/cat /run/user/1000/agenix/token/access-nova.json";
      };
      # Role profiles exported by aws-vault for the user-facing profiles below.
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
    };
  };

  # GUI IDE: Zed
  programs.zed-editor = {
    package = lib.mkForce pkgs.zed-editor; # force, since in devbox it's empty
    installRemoteServer = lib.mkForce false; # GUI needs no server symlink
    # Keep this client-specific
    userSettings = {
      # Right dock width of 250p fit 80-columned code perfectly on 1080p width
      project_panel.default_width = 250;
      git_panel.default_width = 250;
      collaboration_panel.default_width = 250;
      outline_panel.default_width = 250;

      # Don't show ACP terminal response in card
      agent.expand_terminal_card = false;
    };
  };

  # Zed persists dock widths in its state DB (~/.local/share/zed/db/*-stable),
  # not in settings.json — which is a read-only store symlink anyway. The
  # `default_width` above is only a seed: it applies when no row exists, so a
  # single accidental drag pins that panel forever and no `switch` undoes it.
  # Drop those rows at login to make the widths above authoritative again.
  # NOTE: only meaningful while Zed is closed; a running Zed re-serializes
  # panel state from memory on exit, overwriting whatever we delete here.
  systemd.user.services.zed-reset-dock-width = {
    Unit.Description = "Reset Zed sidebar widths to the declarative defaults";
    Service = {
      Type = "oneshot";
      ExecStart = toString (
        pkgs.writeShellScript "zed-reset-dock-width" ''
          set -eu
          # Panel names are Zed's `persistent_name()`, which is the struct name
          # and NOT the settings key: `collaboration_panel` is `CollabPanel`.
          panels="'ProjectPanel', 'GitPanel', 'CollabPanel', 'OutlinePanel'"
          # Keys are `<workspace_id>:<PanelName>`, so match on the suffix to
          # cover every workspace. Other panels (terminal, agent) are left be.
          for db in "$HOME"/.local/share/zed/db/*-stable/db.sqlite; do
            [ -e "$db" ] || continue
            # Absent on a first-run DB whose migrations have not yet applied.
            table=$(${lib.getExe' pkgs.sqlite "sqlite3"} "$db" \
              "SELECT name FROM sqlite_master
                WHERE type = 'table' AND name = 'scoped_kv_store';")
            [ -n "$table" ] || continue
            ${lib.getExe' pkgs.sqlite "sqlite3"} "$db" \
              "DELETE FROM scoped_kv_store
                WHERE namespace = 'dock_panel_size'
                  AND substr(key, instr(key, ':') + 1) IN ($panels);"
          done
        ''
      );
    };
    Install.WantedBy = [ "default.target" ];
  };

  # Nix-built (not auto-downloaded) Zed extensions. Also reaches nova-devbox:
  # remote_extensions on the SSH remote is a live mirror of this client's
  # extensions/installed, pushed on every connect.
  programs.zed-editor-extensions = {
    enable = true;
    packages = with pkgs.zed-extensions; [
      nix
      latex
    ];
  };

  # CLI Agent overrides
  programs.codex.settings.cli_auth_credentials_store = lib.mkForce "keyring";

  # IDE: VSCode official
  programs.vscode = {
    enable = true;
    mutableExtensionsDir = false;
    profiles.default = {
      enableUpdateCheck = false;
      enableExtensionUpdateCheck = false;
      keybindings = [
        {
          key = "ctrl+g"; # Conflicts with Codex and Claude Code CLI
          command = "-workbench.action.terminal.goToRecentDirectory";
          # Technically there's a when clause here, but we don't really need
          # the other one either.
        }
      ];
      extensions =
        with pkgs.vscode-extensions;
        [
          # DevEx
          mkhl.direnv
          ms-vscode-remote.remote-ssh # Unfree

          # Language support
          bbenoist.nix
          unifiedjs.vscode-mdx
          redhat.ansible
          redhat.vscode-yaml
          ms-python.python
          ms-python.vscode-python-envs
          # ms-python.vscode-pylance			# Unfree
          ms-pyright.pyright
          ms-azuretools.vscode-containers

          # Jupyter
          ms-toolsai.jupyter
          ms-toolsai.jupyter-renderers
          ms-toolsai.jupyter-keymap
          ms-toolsai.vscode-jupyter-cell-tags
          ms-toolsai.vscode-jupyter-slideshow

          # Agents integration
          anthropic.claude-code # Unfree
        ]
        ++ (with pkgs.nix-vscode-extensions.vscode-marketplace-release; [
          openai.chatgpt
          github.vscode-codeql # Unfree
        ]);
      userSettings = {
        "update.mode" = "none";
        "editor.tabSize" = 2;
        "editor.minimap.enabled" = false;
        "extensions.autoUpdate" = "off";
        "extensions.autoCheckUpdates" = false;
        "terminal.integrated.defaultProfile.linux" = "zsh";
        "terminal.integrated.initialHint" = false;
        "redhat.telemetry.enabled" = false;

        # Copilot
        "window.commandCenter" = false;
        "editor.inlineSuggest.enabled" = false; # Trigger with Alt + \
        # Modify with `editor.inlineSuggest.trigger`
        # "chat.commandCenter.enabled" = false;
        "chat.viewSessions.orientation" = "stacked";
        # "github.copilot.nextEditSuggestions.enabled" = false; # Red and green boxes

        # Extension: direnv
        "direnv.restart.automatic" = false;

        # Extension: Claude Code
        "claudeCode.useTerminal" = true;
        "claudeCode.preferredLocation" = "panel";
        # "claudeCode.disableLoginPrompt" = true;

        # Extension: Container
        "containers.containerClient" = "com.microsoft.visualstudio.containers.podman";
        "containers.orchestratorClient" =
          "com.microsoft.visualstudio.orchestrators.podmancompose";

        # Extension: CodeQL
        "codeQL.githubDatabase.download" = "never";
        "codeQL.runningQueries.memory" = 8192;
      };
    };
  };

}
