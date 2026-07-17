{ config, lib, pkgs, ... }: {
  # Printing
	services.printing.enable = true;
	# No Avahi

	# Malone 3rd floor printer via AppSocket (JetDirect, port 9100)
	# IPP (port 631) doesn't work
	# DNS also doesn't seem to work
	services.printing.drivers = [ pkgs.hplip ];

	# URI is a secret (see aspect/secret.nix): decrypted to
	# /run/agenix/network/malone-360-printer-uri at activation and read when this
	# service starts. Replaces hardware.printers.ensurePrinters, whose
	# deviceUri is eval-time and leaks into the world-readable nix store.
	systemd.services.ensure-printers = {
		description = "Ensure CUPS printers (URI from agenix)";
		wantedBy = [ "multi-user.target" ];
		requires = [ "cups.service" ];
		after = [ "cups.service" ];
		serviceConfig = {
			Type = "oneshot";
			RemainAfterExit = true;
		};
		script = ''
			${pkgs.cups}/bin/lpadmin -p Office -E \
				-v "$(cat ${config.age.secrets."network/malone-360-printer-uri".path})" \
				-m HP/hp-laserjet_600_m601_m602_m603-ps.ppd.gz \
				-L "Malone 360" \
				-o HPOption_Duplexer=True
			${pkgs.cups}/bin/lpadmin -d Office
		'';
	};
}
