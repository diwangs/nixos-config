/*
  Claude Code CLI sandboxed bash Linux patch

  Claude Code ships with a sandboxed bash feature (`bwrap` on Linux) that
  prevents bash from reading or writing into sensitive directories. It ships
  with a list (e.g., .zshrc, etc.) that it will bind to `/dev/null`. However,
  `bwrap` needs the file to actually exist outside of the sandbox.

  Anthropic, in their infinite wisdom, decided that if the file doesn't exist,
  it will create a new empty file to make bwrap works with the list.
  Unfortunately, it doesn't do a good job at cleaning this up (no unmount). As
  of 2.1.204, bash tool call inside the sandbox will leave some stub files
  outside of the sandbox.

  This patch does three things:
  - Wraps the `bwrap` call inside Claude Code with `unshare` so that all stub
  		files are cleanly unmounted post-call, preparing the way for `rm` when
  		they are ready to be removed. Especially important for `MS_SHARED`.
  - Swaps the `/dev/null` source of every masked-file bind for a real empty
  		regular file. Sensitive paths (`.zshrc`, `.gitmodules`, etc. -- part of
  		the sandbox's read-only mask list, notably `.git/commondir` because of
  		CVE-2026-55607) get bind-mounted from `/dev/null`, which is a character
  		device. On any filesystem mounted `nodev` (as our `/etc/nixos` btrfs
  		subvolume is), opening a device node through the mount is rejected by
  		the kernel with EACCES -- e.g. libgit2 failing to parse `.gitmodules`
  		with "is locked: Permission denied". A regular-file bind isn't subject
  		to `nodev`, so it works everywhere `/dev/null` did plus nodev mounts.
  		`.git/commondir` additionally needs real content, not just emptiness:
  		an empty/"." commondir is fine for the git CLI (it resolves relative to
  		the `.git` dir containing the file, i.e. to itself) but libgit2 -- used
  		by `nix` for `git+file://` fetches -- resolves it differently and fails
  		to find the repository. So it gets the absolute path of the real `.git`
  		directory (derived from the bind target itself) instead, fed to `bwrap
  		--ro-bind-data` via an fd from process substitution so no host temp
  		file (and thus no cleanup, keeping the tail-call `exec`) is needed.
  - Fix an issue where a change in NixOS generation would change the path of
  		the symlinked wrapper.

  Currently, the cleanup themselves are handled by hooks to avoid issues with
  tool call timeout and concurrency.
*/

final: prev:
let
  # Regular-file stand-in for /dev/null: bind-mounting the real device node
  # onto a path under a `nodev` filesystem makes it unopenable (EACCES).
  emptyFile = final.writeText "claude-sandbox-empty" "";

  bwrapShim = final.writeShellScriptBin "bwrap" ''
    		args=(); n=$#; i=1
    		while [ "$i" -le "$n" ]; do
    			a="''${@:$i:1}"; b="''${@:$((i + 1)):1}"; c="''${@:$((i + 2)):1}"
    			if [ "$a" = "--ro-bind" ] && [ "$b" = "/dev/null" ]; then
    				if [ "''${c%/.git/commondir}" != "$c" ]; then
    					exec {fd}< <(printf '%s\n' "''${c%/commondir}")
    					args+=( --ro-bind-data "$fd" "$c" ); i=$((i + 3))
    				else
    					args+=( --ro-bind ${emptyFile} "$c" ); i=$((i + 3))
    				fi
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
in
{
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
