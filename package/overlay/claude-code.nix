/*	
 * Claude Code CLI sandboxed bash Linux patch 
 * 	
 * Claude Code ships with a sandboxed bash feature (`bwrap` on Linux) that
 * prevents bash from reading or writing into sensitive directories. It ships
 * with a list (e.g., .zshrc, etc.) that it will bind to `/dev/null`. However,
 * `bwrap` needs the file to actually exist outside of the sandbox.
 * 
 * Anthropic, in their infinite wisdom, decided that if the file doesn't exist,
 * it will create a new empty file to make bwrap works with the list. 
 * Unfortunately, it doesn't do a good job at cleaning this up (no unmount). As
 * of 2.1.204, bash tool call inside the sandbox will leave some stub files 
 * outside of the sandbox.
 * 
 * This patch does three things:
 * - Wraps the `bwrap` call inside Claude Code with `unshare` so that all stub
 * 		files are cleanly unmounted post-call, preparing the way for `rm` when 
 * 		they are ready to be removed. Especially important for `MS_SHARED`.
 * - Special handling of `.git/commondir` where, because of CVE-2026-55607, it
 * 		is included as part of the sensitive list as read-only. Empty commondir
 * 		causes any git operation inside the sandbox to fail. Thus, if missing 
 * 		outside the sandbox (main branch), fill it with "." instead.
 * - Fix an issue where a change in NixOS generation would change the path of 
 * 		the symlinked wrapper.
 * 
 * Currently, the cleanup themselves are handled by hooks to avoid issues with
 * tool call timeout and concurrency.
 */

final: prev: let
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
