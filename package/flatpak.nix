# Flatpak packages: synchronized in cloud, or official version of packages that
# supposed to be in home-manager

{ config, pkgs, lib, ... }: {
	services.flatpak = {
		packages = [
			# Cloud
			"com.bitwarden.desktop"							# Official!
			"com.spotify.Client"
			"com.valvesoftware.Steam"

			# Gossip
			"com.discordapp.Discord"            # Official!
			"org.signal.Signal"
			"us.zoom.Zoom"
			"com.slack.Slack"

			# Local media (install via flatpak only if official for faster update)
			"app.zen_browser.zen"								# Official!
			"com.moonlight_stream.Moonlight"    # Official!
			"com.brave.Browser"                 # Official!
			"md.obsidian.Obsidian"              # Official!
		];

		# Many packages need X11 socket (not fallback-x11) to open
		overrides = lib.recursiveUpdate (lib.listToAttrs 
			(builtins.map (pkg: {
				name = pkg;
				value = { Context.sockets = [ "wayland" "x11" ]; };
			}) [
				"com.bitwarden.desktop"
				"com.spotify.Client"
				"com.valvesoftware.Steam"

				"com.discordapp.Discord"
				"org.signal.Signal"
				"us.zoom.Zoom"
				
				"com.brave.Browser"
				"md.obsidian.Obsidian"
			])) 
			# Misc specific overrides
			{
				# "org.signal.Signal" = { 
				# 	# https://github.com/flathub/org.signal.Signal/issues/752
				# 	# https://community.signalusers.org/t/warning-do-not-update-from-flathub-database-error/63222/17
				# 	Environment.SIGNAL_PASSWORD_STORE="basic";
				# };
			};
	};
}
