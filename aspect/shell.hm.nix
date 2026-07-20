# Shell configuration shared between the laptop and rootless devboxes
# (imported by home-manager.devbox.nix, which the laptop entry also
# imports). Keep this file devbox-safe: no desktop, dconf, or NixOS-module
# assumptions.
{
  config,
  ...
}:
{
  # Shell
  programs.zsh = {
    enable = true; # also required by home-manager `sshAuthSock` to export SSH_AUTH_SOCK
    # Keep the generated zsh config under $XDG_CONFIG_HOME rather than $HOME
    # (the upcoming home-manager default as of state version 26.05). home-manager
    # bootstraps ZDOTDIR through a managed ~/.zshenv symlink; that used to break
    # Claude Code's bubblewrap sandbox (bwrap cannot bind onto a symlink), which
    # is why this used to disable the symlink and materialize a real ~/.zshenv.
    # The Bash sandbox is landstrip (Landlock) now — no bind-mounts — so the
    # symlink is fine and that whole workaround is gone.
    dotDir = "${config.xdg.configHome}/zsh";
    historySubstringSearch.enable = true; # The only feature I need from OMZ
    autosuggestion.enable = true;
    enableCompletion = true;
    syntaxHighlighting.enable = true;
  };

  programs.starship = {
    # Prompt theming
    enable = true;
    enableZshIntegration = true;
    # No settings, just use the `pure` shell
  };
}
