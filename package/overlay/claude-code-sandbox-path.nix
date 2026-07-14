# Wraps `claude` so the OS-level Bash sandbox (see the `sandbox` settings in
# ../home-manager.devbox.nix) gets inputs it can reliably bind: every PATH
# entry is resolved to its symlink-free target, while dangling, empty, and
# NixOS /run/wrappers entries are dropped (readlink -e, unlike -f, requires
# the target to exist). Static env the wrapper used to export (SHELL,
# CLAUDE_CODE_SHELL, CLAUDE_BASH_NO_LOGIN) lives in settings.json `env`
# instead (../home-manager.devbox.nix).
#
# The sandbox also deny-write-masks the literal $HOME/.z* rc files with bwrap
# binds, and bwrap hard-fails when a bind destination is a symlink. That used
# to force a materialize/restore dance here for the Home Manager zsh symlinks;
# it is gone now that programs.zsh.dotDir keeps them under $XDG_CONFIG_HOME/zsh
# and the ZDOTDIR bootstrap ~/.zshenv is a real file
# (../../system/aspect/shell.hm.nix).

# NixOS exposes setuid wrappers via a generation-specific symlink
# under /run/wrappers. Either spelling can break Claude's bwrap
# setup: the canonical target goes stale after nixos-rebuild, while
# /run/wrappers/bin itself requires bwrap to synthesize a /run parent
# layout it does not always create. Sandboxed Bash should not depend
# on setuid helpers, so keep them out of the sandbox PATH entirely.
final: prev: let
	# Claude Code's Bash sandbox invokes `bwrap`. Shim it so that, for every
	# sandboxed command, the real bwrap runs inside an ephemeral
	# private-propagation mount namespace: `unshare --mount` makes the namespace
	# rprivate, severing this host's MS_SHARED btrfs peer group *before* bwrap
	# creates its deny-binds. Those deny-mounts can then no longer propagate
	# into — and get stuck, unremovable (the namespace has no CAP_SYS_ADMIN, so
	# umount is a no-op and rm hits EBUSY) — the long-lived namespace Claude and
	# `nixos-rebuild` share; they die with the command instead of leaking.
	#
	# It also rewrites the main-worktree commondir mask
	# (`--ro-bind /dev/null <cwd>/.git/commondir`) to a read-only `.` file. The
	# /dev/null mask is unreadable on this host's `nodev` mount and breaks a
	# sandboxed `git status`; a `.` makes git resolve the common dir to `.git`
	# itself (a value git tolerates, unlike libgit2). The bind stays read-only so
	# the CVE-2026-55607 mitigation still holds and only the top-level commondir
	# is touched (linked-worktree commondir handling under .claude/worktrees is
	# left intact). bwrap still creates the commondir bind's mount-point file on
	# the real repo (a write through the rw cwd bind, not a mount that
	# propagation can contain); the rm-only debris hook in
	# ../home-manager.devbox.nix removes that leftover so libgit2/`nixos-rebuild`
	# never see a commondir on disk between commands.
	gitCommondirDot = final.writeText "git-commondir" ".";
	bwrapShim = final.writeShellScriptBin "bwrap" ''
		args=(); n=$#; i=1
		while [ "$i" -le "$n" ]; do
			a="''${@:$i:1}"; b="''${@:$((i + 1)):1}"; c="''${@:$((i + 2)):1}"
			if [ "$a" = "--ro-bind" ] && [ "$b" = "/dev/null" ] \
					&& [ "''${c%/.git/commondir}" != "$c" ]; then
				args+=( --ro-bind ${gitCommondirDot} "$c" ); i=$((i + 3))
			else
				args+=( "$a" ); i=$((i + 1))
			fi
		done
		exec ${final.util-linux}/bin/unshare --mount --map-current-user --propagation private \
			-- ${final.bubblewrap}/bin/bwrap "''${args[@]}"
	'';

	# The upstream claude-code launcher PREPENDS its own baked bin list (which
	# includes the real bubblewrap) to $PATH, so a `bwrap` prepended by this
	# outer wrapper is shadowed and never runs. Deliver the shim by overriding
	# claude-code's `bubblewrap` input instead: it is baked into the launcher's
	# `--prefix PATH`, so the sandbox resolves `bwrap` to the shim. (`bwrap` is
	# the only binary the bubblewrap package provides, so a writeShellScriptBin
	# is a complete drop-in for makeBinPath.)
	claudeCode = prev.claude-code.override { bubblewrap = bwrapShim; };

	claudeWrapper = final.writeShellScript "claude" ''
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

		${claudeCode}/bin/claude "$@"
	'';
in {
	claude-code = final.symlinkJoin {
		name = "${claudeCode.name}-sandbox-path";
		paths = [ claudeCode ];
		postBuild = ''
			rm -f $out/bin/claude
			install -m755 ${claudeWrapper} $out/bin/claude
		'';
		meta = claudeCode.meta;
	};
}
