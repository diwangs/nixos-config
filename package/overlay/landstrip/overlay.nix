# Injects landstrip (the OS-level sandbox runner repackaged in ./package.nix) as
# `pkgs.landstrip`. Import it in ../../../nixos.nix and ../../../flake.nix's
# `nixpkgs.overlays`. See ./package.nix for what consumes it.
final: prev:
let
  upstreamLandstrip = final.callPackage ./package.nix { };
in
{
  landstrip = upstreamLandstrip.overrideAttrs (old: {
    # Downstream policy extension: permit every AF_INET/AF_INET6 socket while
    # retaining AF_UNIX pathname mediation. Exact, one-occurrence semantic
    # anchors make a future upstream source change fail loudly at patch time.
    postPatch = (old.postPatch or "") + ''
      ${final.python3}/bin/python3 - <<'PY'
      from pathlib import Path


      def replace_once(path_text: str, anchor: str, replacement: str) -> None:
          path = Path(path_text)
          source = path.read_text()
          count = source.count(anchor)
          if count != 1:
              raise SystemExit(
                  f"allowAllInetSockets overlay: expected one anchor in {path}, found {count}: {anchor[:80]!r}"
              )
          path.write_text(source.replace(anchor, replacement, 1))


      def insert_after(path: str, anchor: str, addition: str) -> None:
          replace_once(path, anchor, anchor + addition)


      def insert_after_in(
          path_text: str,
          start: str,
          end: str,
          anchor: str,
          addition: str,
      ) -> None:
          path = Path(path_text)
          source = path.read_text()
          start_count = source.count(start)
          end_count = source.count(end)
          if start_count != 1 or end_count != 1:
              raise SystemExit(
                  f"allowAllInetSockets overlay: expected one region in {path}, "
                  f"found start={start_count}, end={end_count}"
              )
          start_index = source.index(start)
          end_index = source.index(end, start_index)
          region = source[start_index:end_index]
          count = region.count(anchor)
          if count != 1:
              raise SystemExit(
                  f"allowAllInetSockets overlay: expected one anchor in {path} region "
                  f"{start!r}, found {count}"
              )
          region = region.replace(anchor, anchor + addition, 1)
          path.write_text(source[:start_index] + region + source[end_index:])


      insert_after(
          "src/engine/config.rs",
          "    pub(crate) allow_network: bool,\n",
          "    pub(crate) allow_all_inet_sockets: bool,\n",
      )

      insert_after(
          "src/engine/policy.rs",
          "pub(crate) struct NetworkAccess {\n",
          "    pub(crate) restrict_inet_socket_types: bool,\n"
          "    pub(crate) restrict_packet_netlink: bool,\n",
      )
      insert_after(
          "src/engine/policy.rs",
          "        Self {\n            restrict_connect_tcp: false,\n",
          "            restrict_inet_socket_types: false,\n"
          "            restrict_packet_netlink: false,\n",
      )
      replace_once(
          "src/engine/policy.rs",
          "        !self.restrict_connect_tcp\n"
          "            && self.connect_tcp_ports.is_empty()\n",
          "        !self.restrict_inet_socket_types\n"
          "            && !self.restrict_packet_netlink\n"
          "            && !self.restrict_connect_tcp\n"
          "            && self.connect_tcp_ports.is_empty()\n",
      )
      replace_once(
          "src/engine/policy.rs",
          "    Ok(NetworkAccess {\n"
          "        restrict_connect_tcp: true,\n"
          "        connect_tcp_ports,\n"
          "        restrict_bind_tcp: !network.allow_local_binding,\n"
          "        local_tcp_bind: network.allow_local_binding,\n"
          "        unix_socket_access,\n"
          "    })\n",
          "    Ok(NetworkAccess {\n"
          "        restrict_inet_socket_types: !network.allow_all_inet_sockets,\n"
          "        restrict_packet_netlink: true,\n"
          "        restrict_connect_tcp: !network.allow_all_inet_sockets,\n"
          "        connect_tcp_ports,\n"
          "        restrict_bind_tcp: !network.allow_all_inet_sockets && !network.allow_local_binding,\n"
          "        local_tcp_bind: !network.allow_all_inet_sockets && network.allow_local_binding,\n"
          "        unix_socket_access,\n"
          "    })\n",
      )

      replace_once(
          "src/engine/platform/linux/filter.rs",
          "pub(super) fn build_errno_filter(\n"
          "    syscalls: &NotificationSyscalls,\n"
          "    needs_network: bool,\n"
          "    unix_sockets: UnixSocketFilter,\n"
          ") -> Result<Option<BpfProgram>> {\n"
          "    let mut errno_rules = RuleMap::new();\n"
          "    if needs_network {\n"
          "        add_socket_family_filter(&mut errno_rules, syscalls.socket)?;\n"
          "        add_unix_socket_filters(&mut errno_rules, syscalls.socket, unix_sockets)?;\n"
          "    }\n",
          "pub(super) fn build_errno_filter(\n"
          "    syscalls: &NotificationSyscalls,\n"
          "    restrict_inet_socket_types: bool,\n"
          "    restrict_packet_netlink: bool,\n"
          "    unix_sockets: UnixSocketFilter,\n"
          ") -> Result<Option<BpfProgram>> {\n"
          "    let mut errno_rules = RuleMap::new();\n"
          "    if restrict_inet_socket_types {\n"
          "        add_inet_socket_type_filters(&mut errno_rules, syscalls.socket)?;\n"
          "    }\n"
          "    if restrict_packet_netlink {\n"
          "        add_packet_netlink_filters(&mut errno_rules, syscalls.socket)?;\n"
          "    }\n"
          "    add_unix_socket_filters(&mut errno_rules, syscalls.socket, unix_sockets)?;\n",
      )
      replace_once(
          "src/engine/platform/linux/filter.rs",
          "pub(super) fn network_filter(config: NetworkFilter, needs_network: bool) -> Result<NetworkFilters> {\n"
          "    let syscalls = NotificationSyscalls::new();\n"
          "    let errno = build_errno_filter(&syscalls, needs_network, config.unix_sockets)?;\n",
          "pub(super) fn network_filter(config: NetworkFilter) -> Result<NetworkFilters> {\n"
          "    let syscalls = NotificationSyscalls::new();\n"
          "    let errno = build_errno_filter(\n"
          "        &syscalls,\n"
          "        config.restrict_inet_socket_types,\n"
          "        config.restrict_packet_netlink,\n"
          "        config.unix_sockets,\n"
          "    )?;\n",
      )
      insert_after(
          "src/engine/platform/linux/filter.rs",
          "pub(super) struct NetworkFilter {\n",
          "    pub(super) restrict_inet_socket_types: bool,\n"
          "    pub(super) restrict_packet_netlink: bool,\n",
      )
      replace_once(
          "src/engine/platform/linux/filter.rs",
          "pub(super) fn add_socket_family_filter(rules: &mut RuleMap, socket: i64) -> Result<()> {\n",
          "pub(super) fn add_inet_socket_type_filters(rules: &mut RuleMap, socket: i64) -> Result<()> {\n",
      )
      replace_once(
          "src/engine/platform/linux/filter.rs",
          "    for domain in [libc::AF_PACKET, libc::AF_NETLINK] {\n"
          "        add_socket_domain_filter(rules, socket, domain)?;\n"
          "    }\n\n"
          "    Ok(())\n"
          "}\n\n"
          "fn add_socket_domain_filter",
          "    Ok(())\n"
          "}\n\n"
          "pub(super) fn add_packet_netlink_filters(rules: &mut RuleMap, socket: i64) -> Result<()> {\n"
          "    for domain in [libc::AF_PACKET, libc::AF_NETLINK] {\n"
          "        add_socket_domain_filter(rules, socket, domain)?;\n"
          "    }\n\n"
          "    Ok(())\n"
          "}\n\n"
          "fn add_socket_domain_filter",
      )

      replace_once(
          "src/engine/platform/linux/mod.rs",
          "        let filters = filter::network_filter(\n"
          "            NetworkFilter {\n"
          "                notify_bind: false,\n"
          "                notify_connect: false,\n"
          "                notify_filesystem: false,\n"
          "                unix_sockets: filter::unix_socket_filter(&network.unix_socket_access),\n"
          "            },\n"
          "            true,\n"
          "        )?;\n",
          "        let filters = filter::network_filter(NetworkFilter {\n"
          "            restrict_inet_socket_types: network.restrict_inet_socket_types,\n"
          "            restrict_packet_netlink: network.restrict_packet_netlink,\n"
          "            notify_bind: false,\n"
          "            notify_connect: false,\n"
          "            notify_filesystem: false,\n"
          "            unix_sockets: filter::unix_socket_filter(&network.unix_socket_access),\n"
          "        })?;\n",
      )

      replace_once(
          "src/engine/platform/linux/seccomp.rs",
          "    let errno = build_errno_filter(&syscalls, needs_network, unix_sockets)?;\n",
          "    let errno = build_errno_filter(\n"
          "        &syscalls,\n"
          "        policy.network_access.restrict_inet_socket_types,\n"
          "        policy.network_access.restrict_packet_netlink,\n"
          "        unix_sockets,\n"
          "    )?;\n",
      )
      insert_after_in(
          "src/engine/platform/linux/seccomp.rs",
          "fn handle_bind(\n",
          "fn handle_connect(\n",
          "    let socket = target_socket(request)?;\n",
          "    if matches!(socket.info.domain, libc::AF_INET | libc::AF_INET6)\n"
          "        && !policy.network_access.restrict_inet_socket_types\n"
          "        && !policy.network_access.restrict_bind_tcp\n"
          "    {\n"
          "        return Ok(NotificationResult::Continue);\n"
          "    }\n",
      )
      insert_after_in(
          "src/engine/platform/linux/seccomp.rs",
          "fn handle_connect(\n",
          "fn handle_unix_bind(\n",
          "    let socket = target_socket(request)?;\n",
          "    if matches!(socket.info.domain, libc::AF_INET | libc::AF_INET6)\n"
          "        && !policy.network_access.restrict_inet_socket_types\n"
          "        && !policy.network_access.restrict_connect_tcp\n"
          "    {\n"
          "        return Ok(NotificationResult::Continue);\n"
          "    }\n",
      )

      insert_after(
          "README.md",
          '    "allowNetwork": false,\n',
          '    "allowAllInetSockets": false,\n',
      )
      insert_after(
          "README.md",
          "limits, traps, and exit status are in the manual page.\n",
          "\nOn Linux, `network.allowAllInetSockets` permits all AF_INET and AF_INET6\n"
          "sockets without changing Unix-socket policy.\n",
      )

      replace_once(
          "tests/data.rs",
          "use std::net::{IpAddr, Ipv4Addr, Ipv6Addr, TcpListener, UdpSocket};\n",
          "use std::net::{IpAddr, Ipv4Addr, Ipv6Addr, TcpListener, TcpStream, UdpSocket};\n",
      )
      insert_after(
          "tests/data.rs",
          "const OPATH_PROBE_ARG: &str = \"--test-opath\";\n",
          "const INET_PROBE_ARG: &str = \"--test-inet\";\n",
      )
      insert_after(
          "tests/data.rs",
          "        Some(value) if value == std::ffi::OsStr::new(FUTIMENS_PROBE_ARG) => {\n"
          "            std::process::exit(futimens_probe(args.next()));\n"
          "        }\n",
          "        Some(value) if value == std::ffi::OsStr::new(INET_PROBE_ARG) => {\n"
          "            std::process::exit(inet_probe());\n"
          "        }\n",
      )
      insert_after("tests/data.rs", "enum Net {\n", "    InetAllowed,\n")
      insert_after(
          "tests/data.rs",
          "        \"listener-denied\" => Net::ListenerDenied,\n",
          "        \"inet-allowed\" => Net::InetAllowed,\n",
      )
      insert_after(
          "tests/data.rs",
          "    match net {\n",
          "        Net::InetAllowed => run_inet_allowed(ctx, format, policies),\n",
      )
      replace_once(
          "tests/data.rs",
          "fn run_listener(\n",
          """fn run_inet_allowed(
          ctx: &Context,
          format: PolicyFormat,
          policies: &[PathBuf],
      ) -> Result<(), String> {
          let output = landstrip_net(ctx, format, policies)
              .arg(&ctx.bin)
              .arg(INET_PROBE_ARG)
              .stdout(Stdio::piped())
              .stderr(Stdio::piped())
              .output()
              .map_err(|error| format!("spawn inet probe: {error}"))?;
          if output.status.success() {
              Ok(())
          } else {
              Err(format!(
                  "inet probe failed: {}",
                  merge(&output.stdout, &output.stderr).trim()
              ))
          }
      }

      fn inet_probe() -> i32 {
          let Ok(tcp4) = TcpListener::bind((Ipv4Addr::LOCALHOST, 0)) else {
              return 1;
          };
          let Ok(tcp4_addr) = tcp4.local_addr() else {
              return 1;
          };
          if TcpStream::connect(tcp4_addr).is_err() {
              return 1;
          }

          let Ok(udp4_receiver) = UdpSocket::bind((Ipv4Addr::LOCALHOST, 0)) else {
              return 1;
          };
          let Ok(udp4_sender) = UdpSocket::bind((Ipv4Addr::LOCALHOST, 0)) else {
              return 1;
          };
          let Ok(udp4_addr) = udp4_receiver.local_addr() else {
              return 1;
          };
          if udp4_sender.connect(udp4_addr).is_err() || udp4_sender.send(b"ok").is_err() {
              return 1;
          }

          if let Ok(tcp6) = TcpListener::bind((Ipv6Addr::LOCALHOST, 0)) {
              let Ok(tcp6_addr) = tcp6.local_addr() else {
                  return 1;
              };
              if TcpStream::connect(tcp6_addr).is_err() {
                  return 1;
              }

              let Ok(udp6_receiver) = UdpSocket::bind((Ipv6Addr::LOCALHOST, 0)) else {
                  return 1;
              };
              let Ok(udp6_sender) = UdpSocket::bind((Ipv6Addr::LOCALHOST, 0)) else {
                  return 1;
              };
              let Ok(udp6_addr) = udp6_receiver.local_addr() else {
                  return 1;
              };
              if udp6_sender.connect(udp6_addr).is_err() || udp6_sender.send(b"ok").is_err() {
                  return 1;
              }
          }

          #[cfg(target_os = "linux")]
          for family in [libc::AF_PACKET, libc::AF_NETLINK] {
              // SAFETY: socket has no borrowed pointers; a successful fd is closed.
              let fd = unsafe { libc::socket(family, libc::SOCK_DGRAM, 0) };
              if fd >= 0 {
                  // SAFETY: fd was returned by socket and is owned by this probe.
                  unsafe { libc::close(fd) };
                  return 1;
              }
              if std::io::Error::last_os_error().raw_os_error() != Some(libc::EAFNOSUPPORT) {
                  return 1;
              }
          }

          0
      }

      fn run_listener(
      """,
      )

      insert_after(
          "tests/data.txt",
          "# --- TCP listeners ---\n\n",
          "name=allowAllInetSockets permits IPv4 IPv6 TCP and UDP | os=linux | policy={\"network\":{\"allowAllInetSockets\":true},\"filesystem\":{\"denyRead\":[\"/\"],\"allowRead\":[\"/\"]}} | net=inet-allowed\n",
      )
      insert_after(
          "tests/data.txt",
          "# --- unix domain sockets (macOS) ---\n\n",
          "name=allowAllInetSockets retains unix socket denial | os=linux | policy={\"network\":{\"allowAllInetSockets\":true},\"filesystem\":{\"denyRead\":[\"/\"],\"allowRead\":[\"/\"]}} | net=unix-denied\n"
          "name=allowNetwork retains legacy unix socket bypass | os=linux | setup=mkdir:unix-sockets | policy={\"network\":{\"allowNetwork\":true},\"filesystem\":{\"denyRead\":[\"/\"],\"allowRead\":[\"/\"]}} | net=unix-allowed | unixsock=unix-sockets/legacy.sock\n",
      )

      required = {
          "src/engine/config.rs": "allow_all_inet_sockets",
          "src/engine/policy.rs": "restrict_inet_socket_types",
          "src/engine/platform/linux/filter.rs": "add_packet_netlink_filters",
          "src/engine/platform/linux/seccomp.rs": "!policy.network_access.restrict_inet_socket_types",
          "tests/data.txt": "allowAllInetSockets permits IPv4 IPv6 TCP and UDP",
      }
      for path_text, needle in required.items():
          if needle not in Path(path_text).read_text():
              raise SystemExit(f"allowAllInetSockets overlay: postcondition missing in {path_text}: {needle}")
      PY
    '';
  });
}
