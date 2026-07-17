final: prev: let
	pcrlockHelper = final.writeShellApplication {
		name = "fwupd-pcrlock-helper";
		text = ''
			PCRLOCK=${final.lib.escapeShellArg "${final.systemd}/lib/systemd/systemd-pcrlock"}
			SYSTEMCTL=${final.lib.escapeShellArg "${final.systemd}/bin/systemctl"}
			'' + builtins.readFile ./helper.sh;
	};
in {
	fwupd = prev.fwupd.overrideAttrs (old: {
		postPatch = (old.postPatch or "") + ''
			cp -R ${./plugin} plugins/pcrlock
			chmod -R u+w plugins/pcrlock

			substituteInPlace plugins/meson.build \
				--replace-fail \
				"'uefi-capsule': false," \
				"'uefi-capsule': false, 'pcrlock': false,"
			substituteInPlace plugins/pcrlock/fu-pcrlock-plugin.c \
				--replace-fail "@PCRLOCK_HELPER@" \
					"${pcrlockHelper}/bin/fwupd-pcrlock-helper" \
				--replace-fail "@PCRLOCK_STATE@" \
					"/run/fwupd-pcrlock/state.ini"
		'';
	});
}
