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

{ lib, ... }: {
  # Bluetooth
  hardware.bluetooth.enable = true;

  # Internet connection manager: NetworkManager (for GUI support)
  networking.networkmanager = {
    enable = true;
    ethernet.macAddress = "stable";
    # Enable native CLAT automatically on IPv6-only connections. NetworkManager
    # learns the PREF64 from router advertisements and translates with BPF.
    connectionConfig."ipv4.clat" = 1;
    # wifi.backend = "iwd";	# iwd is newer, but buggy support for MSCHAPv2 with NM

    # Prioritize dnscrypt-proxy before DHCP-supplied one
    # We do this in Nix instead of NM since NM _replaces_ resolv.conf instead of prepend
    insertNameservers = [ "::1" ];
  };
  networking.nameservers = lib.mkForce [ ]; # Prevent override by dnscrypt-proxy
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

  networking.networkmanager.wifi.macAddress = "random"; # Prevent tracking via MAC address

  # Open ports in the firewall.
  networking.firewall = {
    enable = true; # Enabled by default, but just to make it explicit
    checkReversePath = "loose"; # Disables rpfilter for Wireguard

    # Prioritize IPv6 game-streaming traffic (DSCP CS6). USB/IP server replies
    # use TCP source port 3240, while Moonlight sends UDP traffic to ports
    # 47998-48000. Add the rules idempotently for firewall reloads.
    extraCommands = ''
      ip6tables -w -t mangle -C OUTPUT -p tcp --sport 3240 -j DSCP --set-dscp 48 2>/dev/null || \
        ip6tables -w -t mangle -A OUTPUT -p tcp --sport 3240 -j DSCP --set-dscp 48
      ip6tables -w -t mangle -C OUTPUT -p udp --dport 47998:48000 -j DSCP --set-dscp 48 2>/dev/null || \
        ip6tables -w -t mangle -A OUTPUT -p udp --dport 47998:48000 -j DSCP --set-dscp 48
    '';
    extraStopCommands = ''
      ip6tables -w -t mangle -D OUTPUT -p tcp --sport 3240 -j DSCP --set-dscp 48 2>/dev/null || true
      ip6tables -w -t mangle -D OUTPUT -p udp --dport 47998:48000 -j DSCP --set-dscp 48 2>/dev/null || true
    '';

    # Interfaces
    # Home dock 	-> enp103s0 (Ryzen 7040), enp136s0 (Chromebook)
    # Office dock -> enp101s0 (Ryzen 7040), enp134s0 (Chromebook)
    interfaces.enp103s0.allowedTCPPorts = [
      3240 # USB/IP for Moonlight streaming when necessary
    ];
  };

  # Enable Tor SOCKS5 proxy
  # NetworkManager provides native CLAT when Tor needs IPv4 on IPv6-only links.
  services.tor.enable = true;
  services.tor.client = {
    enable = true;
    socksListenAddress = {
      IsolateDestAddr = true;
      addr = "[::1]";
      port = 9050;
    };
  };
  # Trezor Suite's external Tor integration uses IPv4 loopback.
  services.tor.settings.SOCKSPort = lib.mkAfter [
    {
      IsolateDestAddr = true;
      addr = "127.0.0.1";
      port = 9050;
    }
  ];

  # ===========================================================================
  # DNS64 for IPv6-only networks using NetworkManager's native CLAT
  # ===========================================================================

  # dnscrypt-proxy: DNS64 over HTTPS over Tor
  services.dnscrypt-proxy = {
    enable = true;
    settings = {
      # =======================================================================
      # Upstream: Cloudflare and Google DNS64
      # =======================================================================

      # Netprobe is necessary for bootstrap and works through native CLAT.
      netprobe_address = "1.1.1.1:53";

      # This is done sequentially
      bootstrap_resolvers = [
        "[2606:4700:4700::64]:53" # IPv6 bootstrap for IPv6-only networks
        "9.9.9.9:53" # fallback resolver for IPv4-only network
        "[2606:4700:4700::6400]:53"
        "149.112.112.112:53"
      ];

      # DNS64 servers that support DoH
      # Somehow Tor will handle accessing this through IPv4
      static = {
        "cloudflare-dns64-1".stamp =
          "sdns://AgcAAAAAAAAAFFsyNjA2OjQ3MDA6NDcwMDo6NjRdABhkbnM2NC5jbG91ZGZsYXJlLWRucy5jb20KL2Rucy1xdWVyeQ";
        "cloudflare-dns64-2".stamp =
          "sdns://AgcAAAAAAAAAFlsyNjA2OjQ3MDA6NDcwMDo6NjQwMF0AGGRuczY0LmNsb3VkZmxhcmUtZG5zLmNvbQovZG5zLXF1ZXJ5";
        "google-dns64-1".stamp =
          "sdns://AgcAAAAAAAAAFlsyMDAxOjQ4NjA6NDg2MDo6NjQ2NF0AEGRuczY0LmRucy5nb29nbGUKL2Rucy1xdWVyeQ";
        "google-dns64-2".stamp =
          "sdns://AgcAAAAAAAAAFFsyMDAxOjQ4NjA6NDg2MDo6NjRdABBkbnM2NC5kbnMuZ29vZ2xlCi9kbnMtcXVlcnk";
      };
      # Default policy will load balance between the fastest two servers
      server_names = [
        "cloudflare-dns64-1"
        "cloudflare-dns64-2"
        "google-dns64-1"
        "google-dns64-2"
      ];

      proxy = "socks5://[::1]:9050"; # Route via Tor

      # =======================================================================
      # Interfaces: local DNS or DoH server
      # =======================================================================
      listen_addresses = [
        "[::1]:53"
        "127.0.0.1:53"
      ];
      ignore_system_dns = false; # So that it hands back control to resolv?

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
