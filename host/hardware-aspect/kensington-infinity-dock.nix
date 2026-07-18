{ pkgs, ... }:
let
  # Linux > 6.18 configures MSI-X for this I210, but no interrupts arrive.
  # Rebinding with MSI disabled makes the NIC use working legacy INTx. Has some
  # performance penalty, but won't be noticable for 1G ethernet.
  igbIntxWorkaround = pkgs.writeShellScript "igb-intx-workaround" ''
    		set -eu

    		address="$1"
    		device="/sys/bus/pci/devices/$address"

    		[ -d "$device" ] || exit 0
    		[ "$(cat "$device/vendor")" = "0x8086" ] || exit 0
    		[ "$(cat "$device/device")" = "0x1533" ] || exit 0
    		[ "$(cat "$device/subsystem_vendor")" = "0x1d40" ] || exit 0
    		[ "$(cat "$device/subsystem_device")" = "0x9028" ] || exit 0

    		printf 0 > "$device/msi_bus"

    		if [ -L "$device/driver" ] &&
    				[ "$(basename "$(readlink "$device/driver")")" = "igb" ]; then
    			printf '%s' "$address" > "$device/driver/unbind"
    			printf '%s' "$address" > /sys/bus/pci/drivers/igb/bind
    		fi
    	'';
in
{
  services.udev.extraRules = ''
    		ACTION=="add", SUBSYSTEM=="pci", ATTR{vendor}=="0x8086", ATTR{device}=="0x1533", ATTR{subsystem_vendor}=="0x1d40", ATTR{subsystem_device}=="0x9028", ATTR{msi_bus}="0", TAG+="systemd", ENV{SYSTEMD_WANTS}+="igb-intx-workaround@%k.service"
    	'';

  systemd.services."igb-intx-workaround@" = {
    description = "Force legacy INTx for Kensington dock I210 at %I";
    serviceConfig = {
      Type = "oneshot";
      ExecStart = "${igbIntxWorkaround} %I";
    };
  };
}
