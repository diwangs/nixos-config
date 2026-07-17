{ config, lib, pkgs, ... }: {
  # Timezone
	time.timeZone = lib.mkDefault "America/New_York";

	# Automatic timezone (flaky if wifi is not enabled)
	# services.automatic-timezoned.enable = true;
	# services.geoclue2.enableDemoAgent = lib.mkForce true;
  # services.geoclue2.geoProviderUrl = "https://api.beacondb.net/v1/geolocate";

  # Select internationalisation properties.
	# i18n.defaultLocale = "en_US.UTF-8";
	# console = {
	#   font = "Lat2-Terminus16";
	#   keyMap = "us";
	#   useXkbConfig = true; # use xkb.options in tty.
	# };
}