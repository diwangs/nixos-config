# Shell configuration shared between the laptop and rootless devboxes
# (imported by home-manager.devbox.nix, which the laptop entry also
# imports). Keep this file devbox-safe: no desktop, dconf, or NixOS-module
# assumptions.
{ config, pkgs, lib, ... }: {
	# Shell
	programs.zsh = {
		enable = true;	# also required by home-manager `sshAuthSock` to export SSH_AUTH_SOCK
		# Keep the generated zsh config out of $HOME (the upcoming home-manager
		# default). Claude Code's sandbox deny-write-masks the literal $HOME/.z*
		# rc files with bwrap binds, and bwrap hard-fails when a bind destination
		# is a symlink — under $XDG_CONFIG_HOME/zsh the store symlinks live where
		# the sandbox never binds them, so no materialize/restore dance is needed.
		dotDir = "${config.xdg.configHome}/zsh"; # New default as of state version 26.05
		historySubstringSearch.enable = true; # The only feature I need from OMZ
		autosuggestion.enable = true;
		enableCompletion = true;
		syntaxHighlighting.enable = true;
	};

	# With dotDir off $HOME, home-manager still bootstraps ZDOTDIR through a
	# ~/.zshenv *store symlink* — the one zsh file left in $HOME, and a symlink
	# there breaks Claude Code's bwrap sandbox (it cannot bind onto symlinks).
	# Disable home-manager's copy and materialize the same one-liner as a real
	# writable file instead (same pattern as the writable settings.json in
	# ../package/home-manager.devbox.nix). The sweep also drops $HOME/.zshrc
	# and .zprofile left behind by pre-dotDir generations or by the old claude
	# wrapper's EXIT trap; once ZDOTDIR is set nothing reads them.
	home.file.".zshenv".enable = false;
	home.activation.zshenvBootstrap = lib.hm.dag.entryAfter [ "linkGeneration" ] ''
		for name in .zshrc .zprofile; do
			path="$HOME/$name"
			if [ -L "$path" ] || { [ -f "$path" ] && [ ! -s "$path" ]; }; then
				run rm -f "$path"
			fi
		done
		run install -m644 ${pkgs.writeText "zshenv-bootstrap" ''
			source "${config.xdg.configHome}/zsh/.zshenv"
		''} "$HOME/.zshenv"
	'';

	programs.starship = {		# Prompt theming
		enable = true;
		enableZshIntegration = true;
		# No settings, just use the `pure` shell
	};
}
