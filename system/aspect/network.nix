# Networking
#
# - Support for IPv6 only (home): we need some transition mechanism, e.g.
# 	464XLAT CLAT and DNS64. This assumes the network has 464XLAT PLAT 
# 	(which I have). 
# - Support for IPv4 only (hopkins): Whatever modification is done for IPv6
#		only support should not block access through an IPv4 network (esp. DNS)
# - Encrypted DNS: that's ideally synergistic with other
# 	security and privacy mechanism (e.g. TLS 1.3 + ECH, DoHoT).
# - WiFi gateways: whatever complicated DNS setup we have, make sure that 
#		it falls back to the DHCP DNS setting (for gateways, e.g., airports)
#		

{ config, lib, pkgs, ... }: {
	# Bluetooth
	hardware.bluetooth.enable = true;
	
	# Internet connection manager: NetworkManager (for GUI support)
	networking.networkmanager = {
		enable = true;
		ethernet.macAddress = "stable";
		# wifi.backend = "iwd";	# iwd is newer, but buggy support for MSCHAPv2 with NM

		# Prioritize dnscrypt-proxy before DHCP-supplied one
		# We do this in Nix instead of NM since NM _replaces_ resolv.conf instead of prepend
		insertNameservers = [ "::1" ];	
	};
	networking.nameservers = lib.mkForce []; # Prevent override by dnscrypt-proxy
	networking.enableIPv6 = true; # Also enables tempAddresses (privacy ext)
	# ON STATIC IPv6 ADDRESS
	# NetworkManager WiFi doesn't play well with 'Managed' flag in RA
	# Thus, if you want static address, set it on the client instead of static 
	# lease on the router; e.g., for VirtualHere

	# Enables DHCP on each ethernet and wireless interface. In case of scripted 
	# networking (the default) this is the recommended approach. When using 
	# systemd-networkd it's still possible to use this option, but it's 
	# recommended to use it in conjunction with explicit per-interface 
	# declarations with `networking.interfaces.<interface>.useDHCP`.
	networking.useDHCP = lib.mkDefault true;

  # Open ports in the firewall.
	networking.firewall = {
		enable = true; # Enabled by default, but just to make it explicit
		checkReversePath = "loose"; # Disables rpfilter for Wireguard
		
		# Interfaces
		# Home dock 	-> enp103s0 (Ryzen 7040), enp136s0 (Chromebook)
		# Office dock -> enp101s0 (Ryzen 7040), enp134s0 (Chromebook)
    interfaces.enp103s0.allowedTCPPorts = [ 
			3240 # USB/IP for Moonlight streaming when necessary
		];
	};

	# Enable Tor SOCKS5 proxy
	# Tor needs IPv4, so it should wait for clat somehow
	services.tor.enable = true;
	services.tor.client = {
		enable = true;
		socksListenAddress = {
			IsolateDestAddr = true;
			addr = "[::1]";
			port = 9050;
		};
	};

	# ===========================================================================
	# Enable 464XLAT scheme for IPv6 only networks
	# ===========================================================================

	services.clatd.enable = true;

	# tayga > 0.9.2 enforces Well-Known Prefix (wkpf) compliance 
	# according to RFC6052 (wkpf + private IPv4 addr = no bueno), which breaks 
	# CLAT as we know it. We need to change this behavior on the tayga that is 
	# used by clatd. Tried solutions:
	# - clatd's script-up -> doesn't work somehow (error code 1 on `clatd`)
	# - clatd's cmd-tayga + wrapper script -> works, but has longer code
	# - (this) Patch tayga source code -> simplest, might be fragile to updates
	nixpkgs.overlays = [ (final: prev: {
		tayga = prev.tayga.overrideAttrs (old: {
			# Patch conf parser, set value to 0 even if 1 is read (thanks Claude!)
			postPatch = (old.postPatch or "") + ''
				substituteInPlace conffile.c --replace-fail \
					'gcfg->wkpf_strict = 1' 'gcfg->wkpf_strict = 0'
			'';
		});
	})];

	# dnscrypt-proxy: DNS64 over HTTPS over Tor
	services.dnscrypt-proxy = {
		enable = true;
		settings = {
			# =======================================================================
			# Upstream: Cloudflare and Google DNS64
			# =======================================================================

			# Netprobe is necessary for bootstrap, to detect if clatd is running
			netprobe_address = "1.1.1.1:53";

			# This is done sequentially
			bootstrap_resolvers = [ 
				"[2606:4700:4700::64]:53" 	# Make sure this has PREF64 for clatd
				"9.9.9.9:53"								# fallback resolver for IPv4-only network
				"[2606:4700:4700::6400]:53"
				"149.112.112.112:53"
			];

			# DNS64 servers that support DoH
			# Somehow Tor will handle accessing this through IPv4
			static = {
				"cloudflare-dns64-1".stamp = "sdns://AgcAAAAAAAAAFFsyNjA2OjQ3MDA6NDcwMDo6NjRdABhkbnM2NC5jbG91ZGZsYXJlLWRucy5jb20KL2Rucy1xdWVyeQ";
				"cloudflare-dns64-2".stamp = "sdns://AgcAAAAAAAAAFlsyNjA2OjQ3MDA6NDcwMDo6NjQwMF0AGGRuczY0LmNsb3VkZmxhcmUtZG5zLmNvbQovZG5zLXF1ZXJ5";
				"google-dns64-1".stamp = "sdns://AgcAAAAAAAAAFlsyMDAxOjQ4NjA6NDg2MDo6NjQ2NF0AEGRuczY0LmRucy5nb29nbGUKL2Rucy1xdWVyeQ";
				"google-dns64-2".stamp = "sdns://AgcAAAAAAAAAFFsyMDAxOjQ4NjA6NDg2MDo6NjRdABBkbnM2NC5kbnMuZ29vZ2xlCi9kbnMtcXVlcnk";
			};
			# Default policy will load balance between the fastest two servers
			server_names = [ 	
				"cloudflare-dns64-1" 
				"cloudflare-dns64-2"
				"google-dns64-1" 
				"google-dns64-2"
			];

			proxy = "socks5://[::1]:9050";		# Route via Tor

			# =======================================================================
			# Interfaces: local DNS or DoH server
			# =======================================================================
			listen_addresses = [ "[::1]:53" "127.0.0.1:53" ];
			ignore_system_dns = false;		# So that it hands back control to resolv?

			# As of Aug '24, Chrome still rely on their own DNS resolution to 
			# implement ECH on TLS 1.3 servers. To route them over Tor, we create a 
			# local DoH server that receives DoH queries from the browser and 
			# repackage them to Cloudflare or Google over Tor. This requires local 
			# certificate install.
			# https://bugzilla.mozilla.org/show_bug.cgi?id=1500289
			# dnscrypt-proxy wiki said that Chrome can do ECH without its DoH
			# but Brave still does so.
			# Firefox don't need this since it can be configured to use ECH without
			# built-in DoH (i.e., use system DNS resolver) -> turn off DoH in Firefox
		};
	};
}