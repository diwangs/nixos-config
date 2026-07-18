#### Virtualisation
# System-level support for Claude Desktop's Cowork sandbox VM (the `yukonSilver`
# feature). Cowork drives QEMU directly (NOT via libvirt), booting a lightweight
# micro-VM with OVMF firmware + a virtiofsd share. This aspect supplies the two
# pieces the app resolves at the SYSTEM level; the two hardcoded FHS binary
# paths (OVMF, virtiofsd) are redirected into the Nix store by the package patch
# overlay ../package/overlay/claude-desktop/patch/01-cowork-vm-fhs-paths.nix.
#
# The app's startup probe (app.asar) checks:
#   - qemu-system-x86_64 on $PATH                    -> on the claude-desktop wrapper PATH
#   - /dev/kvm + /dev/vhost-vsock openable            -> KVM gate
#   - OVMF firmware + virtiofsd at absolute paths     -> package patch
#
# qemu is now supplied by the claude-desktop package itself (qemu_kvm on its
# wrapper PATH), NOT system-wide — so nothing qemu-related is needed here. All
# that remains a SYSTEM concern is the vhost_vsock kernel module.
#
# On this host /dev/kvm and /dev/vhost-vsock already exist and are world-
# accessible (crw-rw-rw-), and kvm-amd is autoloaded — but the vhost_vsock
# module is NOT loaded by default, so the vsock device is inert until we request
# it. We therefore only need: vhost_vsock loaded at boot. No libvirtd (Cowork
# doesn't use it), and no kvm-group membership (the device is already world-
# accessible; revisit if udev perms are ever tightened).
{ ... }: {
  # vhost_vsock backs /dev/vhost-vsock (host<->guest sockets); the device node
  # exists but the module is unloaded by default. Load it at boot so the app's
  # vsock gate passes. (kvm_amd is already autoloaded by the CPU microcode/KVM
  # init, so it is not listed here.)
  boot.kernelModules = [ "vhost_vsock" ];

	# Enable unprivileged user NS
	# Historically this allows for some CVE, but a bunch of packages rely on this (e.g. chromium-based, Zoom, etc.)
	security.unprivilegedUsernsClone = true;

  # Podman
	virtualisation = {
		containers = {
			enable = true;
			storage.settings = {
				storage = {
					driver = "overlay";
					runroot = "/run/containers/storage";
					graphroot = "/var/lib/containers/storage";
					rootless_storage_path = "/tmp/containers-$USER";
					options.overlay.mountopt = "nodev,metacopy=on";
				};
			};
		};
		oci-containers.backend = "podman";
		podman = {
			enable = true;
			# dockerCompat = true;
			# For `docker-compose`
			defaultNetwork.settings.dns_enabled = true;
		};
	};
	environment.extraInit = ''
    if [ -z "$DOCKER_HOST" -a -n "$XDG_RUNTIME_DIR" ]; then
      export DOCKER_HOST="unix://$XDG_RUNTIME_DIR/podman/podman.sock"
    fi
  '';
}
