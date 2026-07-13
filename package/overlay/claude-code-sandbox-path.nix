# Wraps `claude` so the OS-level Bash sandbox (see the `sandbox` settings in
# ../home-manager.devbox.nix) gets inputs it can reliably bind: zsh startup
# files are materialized if Home Manager linked them into the store and restored
# after Claude exits, every PATH entry is resolved to its symlink-free target,
# while dangling, empty, and NixOS /run/wrappers entries are dropped
# (readlink -e, unlike -f, requires the
# target to exist). Static env
# the wrapper used to export (SHELL, CLAUDE_CODE_SHELL, CLAUDE_BASH_NO_LOGIN)
# lives in settings.json `env` instead (../home-manager.devbox.nix).

# NixOS exposes setuid wrappers via a generation-specific symlink
# under /run/wrappers. Either spelling can break Claude's bwrap
# setup: the canonical target goes stale after nixos-rebuild, while
# /run/wrappers/bin itself requires bwrap to synthesize a /run parent
# layout it does not always create. Sandboxed Bash should not depend
# on setuid helpers, so keep them out of the sandbox PATH entirely.
final: prev: let
	claudeWrapper = final.writeShellScript "claude" ''
		zshrc_target=
		zprofile_target=
		zshenv_target=
		zsh_links_restored=

		restore_zsh_dotfile_link() {
			file=$1
			target=$2

			[ -n "$target" ] || return 0
			if [ ! -e "$file" ] || { [ -f "$file" ] && [ ! -L "$file" ]; }; then
				${final.coreutils}/bin/rm -f -- "$file" || return 0
				${final.coreutils}/bin/ln -s -- "$target" "$file" || true
			fi
		}

		restore_zsh_dotfile_links() {
			[ -z "$zsh_links_restored" ] || return 0
			zsh_links_restored=1

			[ -n "''${HOME:-}" ] || return 0
			restore_zsh_dotfile_link "$HOME/.zshrc" "$zshrc_target"
			restore_zsh_dotfile_link "$HOME/.zprofile" "$zprofile_target"
			restore_zsh_dotfile_link "$HOME/.zshenv" "$zshenv_target"
		}

		trap 'restore_zsh_dotfile_links' EXIT

		if [ -n "''${HOME:-}" ]; then
			for file in "$HOME/.zshrc" "$HOME/.zprofile" "$HOME/.zshenv"; do
				[ -L "$file" ] || continue
				target=$(${final.coreutils}/bin/readlink -f -- "$file") || continue
				[ -f "$target" ] || continue
				case "$file" in
					"$HOME/.zshrc") zshrc_target=$target ;;
					"$HOME/.zprofile") zprofile_target=$target ;;
					"$HOME/.zshenv") zshenv_target=$target ;;
				esac
				${final.coreutils}/bin/rm -f -- "$file" || continue
				${final.coreutils}/bin/install -m644 -- "$target" "$file" || true
			done
		fi

		set -f; IFS=:
		newpath=
		for dir in $PATH; do
			case $dir in
				/run/wrappers|/run/wrappers/*) continue ;;
				*) dir=$(${final.coreutils}/bin/readlink -e -- "$dir") || continue ;;
			esac
			newpath="''${newpath:+$newpath:}$dir"
		done
		export PATH=$newpath

		${prev.claude-code}/bin/claude "$@"
	'';
in {
	claude-code = final.symlinkJoin {
		name = "${prev.claude-code.name}-sandbox-path";
		paths = [ prev.claude-code ];
		postBuild = ''
			rm -f $out/bin/claude
			install -m755 ${claudeWrapper} $out/bin/claude
		'';
		meta = prev.claude-code.meta;
	};
}
