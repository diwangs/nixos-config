#### Virtualisation
# System-level support for Claude Desktop's Cowork sandbox VM (the `yukonSilver`
# feature). Cowork drives QEMU directly (NOT via libvirt), booting a lightweight
# micro-VM with OVMF firmware + a virtiofsd share. This aspect supplies the two
# pieces the app resolves at the SYSTEM level; the two hardcoded FHS binary
# paths (OVMF, virtiofsd) are redirected into the Nix store by the package patch
# overlay ../../package/overlay/claude-desktop/patch/01-cowork-vm-fhs-paths.nix.
#
# The app's startup probe (app.asar) checks:
#   - qemu-system-x86_64 on $PATH                    -> provided here
#   - /dev/kvm + /dev/vhost-vsock openable            -> KVM gate
#   - OVMF firmware + virtiofsd at absolute paths     -> package patch
#
# On this host /dev/kvm and /dev/vhost-vsock already exist and are world-
# accessible (crw-rw-rw-), and kvm-amd is autoloaded — but the vhost_vsock
# module is NOT loaded by default, so the vsock device is inert until we request
# it. We therefore only need: qemu on PATH + vhost_vsock loaded at boot. No
# libvirtd (Cowork doesn't use it), and no kvm-group membership (the device is
# already world-accessible; revisit if udev perms are ever tightened).
{ config, pkgs, lib, ... }: {
  # qemu-host-cpu-only: provides qemu-system-x86_64 for the app's PATH scan with
  # a much smaller closure than full `qemu` (all Cowork needs is x86_64 + KVM).
  environment.systemPackages = [ pkgs.qemu_kvm ];

  # vhost_vsock backs /dev/vhost-vsock (host<->guest sockets); the device node
  # exists but the module is unloaded by default. Load it at boot so the app's
  # vsock gate passes. (kvm_amd is already autoloaded by the CPU microcode/KVM
  # init, so it is not listed here.)
  boot.kernelModules = [ "vhost_vsock" ];
}
