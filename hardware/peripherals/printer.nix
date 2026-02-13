{ config, lib, pkgs, secrets, ... }: {
  # Printing
	services.printing.enable = true;
	# No Avahi

	# Malone 3rd floor printer via AppSocket (JetDirect, port 9100)
	# IPP (port 631) doesn't work
	# DNS also doesn't seem to work
	services.printing.drivers = [ pkgs.hplip ];
	hardware.printers = {
		ensurePrinters = [{
			name = "Office";
			location = "Malone 360";
			deviceUri = secrets.peripherals.printer-uri;
			# DNS doesn't work, IPP doesn't print
			model = "HP/hp-laserjet_600_m601_m602_m603-ps.ppd.gz";
			ppdOptions = {
				"HPOption_Duplexer" = "True";
			};
		}];
		ensureDefaultPrinter = "Office";
	};
}