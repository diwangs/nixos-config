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
  config,
  lib,
  pkgs,
  pkgs-stable,
  ...
}:
let
  # YubiKey PIV slot 9a public key (SSH auth + git signing identity)
  pivSshPubKey = "ecdsa-sha2-nistp256 AAAAE2VjZHNhLXNoYTItbmlzdHAyNTYAAAAIbmlzdHAyNTYAAABBBAlqJuT2Lkccq5Q3Jkc8msxn9FQ1tvtP4i/fvTIpBrjUAB/RayymoXWLQUly3o9ytPcJK1PDI/EuxbdjmxKEaSI=";
in
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

      # Runtime environment (or environment manager)
      conda # Python environment manager	  		(conda-shell)
      ansible
      sshpass
      ansible-lint
      # AWS credential broker: exposes STS keys while keeping the access key in
      # the secret service. Laptop-only (not in the shared devbox list) because
      # its content-type fix for the oo7 backend lives in an overlay wired into
      # nixos.nix (see package/overlay/aws-vault.nix).
      aws-vault # `aws-vault add --secret-service-collection='Login' ...`

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
    signing = {
      # SSH-based signing via the YubiKey PIV key served by yubikey-agent
      # (ssh-keygen -Y sign goes through SSH_AUTH_SOCK; pinentry per session)
      format = "ssh";
      key = "key::${pivSshPubKey}";
    };
    settings = {
      # Lets `git log --show-signature` verify our own signatures
      gpg.ssh.allowedSignersFile = "${config.xdg.configHome}/git/allowed_signers";
      # SSH_AUTH_SOCK is cached by the GNOME environment, restart if changed
      # gpg.ssh.program = "${pkgs.writeShellScript "ssh-keygen-yubikey" ''
      # 	export SSH_AUTH_SOCK="''${SSH_AUTH_SOCK:-''${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/yubikey-agent/yubikey-agent.sock}"
      # 	exec ${pkgs.openssh}/bin/ssh-keygen "$@"
      # ''}";
    };
  };
  xdg.configFile."git/allowed_signers".text = "* ${pivSshPubKey}\n";

  # AWS CLI configuration
  programs.awscli = {
    enable = true;
    settings = {
      # Shim profile; don't use this ("nova" won't resolve)
      "profile diwangs-mantle" = {
        source_profile = "nova"; # Defined inside `aws-vault`
        role_arn = "arn:aws:iam::995133654082:role/diwangs-mantle";
        region = "us-east-1";
      };
      "profile diwangs-mantle-tf" = {
        source_profile = "nova";
        role_arn = "arn:aws:iam::995133654082:role/diwangs-mantle-tf";
        region = "us-east-2";
      };
      # Actual profile
      "profile mantle" = {
        credential_process = "aws-vault export --secret-service-collection='Login' --format=json diwangs-mantle";
      };
      "profile mantle-tf" = {
        credential_process = "aws-vault export --secret-service-collection='Login' --format=json diwangs-mantle-tf";
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

      # agent.default_width = 1080;

      # ssh_connections = [
      #   {
      #     host = "nova-devbox";
      #   }
      # ];
    };
  };

  # Nix-built (not auto-downloaded) Zed extensions. Also reaches nova-devbox:
  # remote_extensions on the SSH remote is a live mirror of this client's
  # extensions/installed, pushed on every connect.
  programs.zed-editor-extensions = {
    enable = true;
    packages = with pkgs.zed-extensions; [
      nix
    ];
  };

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

  # CLI-based agent orchestrator
  programs.t3code = {
    enable = true;
  };
}
