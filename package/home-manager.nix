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

      # Agentic
      claude-desktop
      claude-science
      chatgpt
      hermes-desktop
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
      pkgs-stable.codeql # Pin CodeQL.
    ];

  # Dev (OpenCode, direnv, and gh live in home-manager.headless.nix)
  programs.java = {
    # Aside from installing jdk (latest LTS), this sets JAVA_HOME
    enable = true;
    package = pkgs.jdk25; # Latest LTS
  };

  programs.git = {
    enable = true;
    lfs.enable = true;
  };

  # The desktop uses the login keyring for aws-vault's cache.
  home.sessionVariables.AWS_VAULT_SECRET_SERVICE_COLLECTION_NAME = "login";

  # GUI IDE: Zed (also $EDITOR, e.g. for Claude)
  home.sessionVariables.EDITOR = "zeditor --wait";
  programs.zed-editor = {
    package = lib.mkForce pkgs.zed-editor; # force, to change value in headless
    installRemoteServer = lib.mkForce false; # force too
    # Keep this on the client
    userSettings = {
      edit_predictions.mode = "subtle";

      # Right dock width that leaves space for 80 cols on 1080p potrait
      project_panel.default_width = 220;
      git_panel.default_width = 220;
      collaboration_panel.default_width = 220;
      outline_panel.default_width = 220;

      # Bottom dock height that shows 24 rows on 1080p potrait
      terminal.default_height = 520;
      # 261106: Apparently debug panel has no such setting?

      # Don't show ACP terminal response in card
      agent.expand_terminal_card = false;
    };
  };

  # Nix-built (not auto-downloaded) Zed extensions. Server-pushed on connect.
  programs.zed-editor-extensions = {
    enable = true;
    packages = with pkgs.zed-extensions; [
      nix
      latex
      terraform
    ];
  };

  # Zed persists dock sizes in its state DB (~/.local/share/zed/db/*-stable),
  # not in settings.json — which is a read-only store symlink anyway. The
  # `default_width`/`default_height` above are only seeds: they apply when no
  # row exists, so a single accidental drag pins that panel forever and no
  # `switch` undoes it.
  # Drop those rows at login to make the sizes above authoritative again.
  # NOTE: only meaningful while Zed is closed; a running Zed re-serializes
  # panel state from memory on exit, overwriting whatever we delete here.
  systemd.user.services.zed-reset-dock-width = {
    Unit.Description = "Reset Zed dock sizes to the declarative defaults";
    Service = {
      Type = "oneshot";
      ExecStart = toString (
        pkgs.writeShellScript "zed-reset-dock-width" ''
          set -eu
          # Panel names are Zed's `persistent_name()`, which is the struct name
          # and NOT the settings key: `collaboration_panel` is `CollabPanel`.
          panels="'ProjectPanel', 'GitPanel', 'CollabPanel', 'OutlinePanel',
            'TerminalPanel'"
          # Keys are `<workspace_id>:<PanelName>`, so match on the suffix to
          # cover every workspace. Other panels (e.g. agent) are left be.
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
}
