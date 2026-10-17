{
  disko,
  impermanence,
  lib,
  modulesPath,
  ...
}:
{
  imports = [
    "${modulesPath}/profiles/qemu-guest.nix"
    disko.nixosModules.disko
    impermanence.nixosModules.impermanence
    ./hardware-aspect/sentinel-netx-disk.nix
  ];

  nixpkgs.hostPlatform = "x86_64-linux";
  system.stateVersion = "26.05";

  boot = {
    loader = {
      efi.canTouchEfiVariables = false;
      systemd-boot.enable = true;
      timeout = 3;
    };
    initrd = {
      systemd.enable = true;
      systemd.tpm2.enable = true;
      availableKernelModules = [
        "virtio_pci"
        "virtio_scsi"
        "sd_mod"
      ];
    };
    kernelParams = [ "console=ttyS0" ];
  };

  environment.persistence."/persist/states" = {
    hideMounts = true;
    directories = [
      "/etc/nixos"
      "/etc/systemd/network"
      "/var/lib/containers"
      "/var/lib/nixos"
      "/var/lib/systemd"
      {
        directory = "/home/diwangs";
        user = "diwangs";
        group = "users";
        mode = "0700";
      }
    ];
    files = [ "/etc/machine-id" ];
  };

  environment.persistence."/persist/caches" = {
    hideMounts = true;
    directories = [
      "/var/lib/cloud"
      "/var/lib/pcrlock.d"
      "/var/log"
      "/var/cache"
    ];
    # User-scoped persistence treats the home directory as a permissions
    # boundary. A system-level .cache entry copies its root-owned backing
    # parent's permissions onto /home/diwangs during every activation.
    users.diwangs.directories = [
      {
        directory = ".cache";
        mode = "0700";
      }
    ];
  };

  # Impermanence preserves existing backing-directory permissions, and Disko
  # creates subvolumes as root. Repair both homes and the cache before Home
  # Manager activation, including installations affected by the old entry.
  systemd.tmpfiles.rules = [
    "d /persist/states/home/diwangs 0700 diwangs users - -"
    "d /persist/caches/home/diwangs 0700 diwangs users - -"
    "d /persist/caches/home/diwangs/.cache 0700 diwangs users - -"
  ];

  # Proxmox's NoCloud drive supplies per-clone hostname and IP settings.
  networking = {
    hostName = lib.mkForce "";
    useDHCP = false;
    firewall.allowedTCPPorts = [ 22 ];
  };
  services.cloud-init = {
    enable = true;
    network.enable = true;
    settings = {
      datasource_list = [ "NoCloud" ];
      users = [ ]; # NixOS owns accounts and authorized_keys.
      # NixOS also owns the passwd database and SSH host keys. Cloud-init's
      # defaults try to change both, racing sshd-keygen and failing on the
      # declarative passwd file. Keep only metadata and network setup.
      cloud_init_modules = [
        "migrator"
        "seed_random"
        "bootcmd"
        "write-files"
        "update_hostname"
        "resolv_conf"
        "ca-certs"
        "rsyslog"
      ];
      cloud_config_modules = [
        "disk_setup"
        "mounts"
        "timezone"
        "disable-ec2-metadata"
        "runcmd"
      ];
      disable_root = true;
      ssh_pwauth = false;
      preserve_hostname = false;
      package_upgrade = false;
    };
  };
  services.qemuGuest.enable = true;
  virtualisation.podman.enable = true;
  services.openssh = {
    enable = true;
    # Do not persist /etc/ssh itself: that hides NixOS's generated sshd_config
    # and authorized_keys.d. The host keys alone live on the state subvolume.
    hostKeys = [
      {
        type = "rsa";
        bits = 4096;
        path = "/persist/states/etc/ssh/ssh_host_rsa_key";
      }
      {
        type = "ed25519";
        path = "/persist/states/etc/ssh/ssh_host_ed25519_key";
      }
    ];
    settings = {
      PasswordAuthentication = false;
      KbdInteractiveAuthentication = false;
      PermitRootLogin = "no";
    };
  };
  users.users.diwangs.openssh.authorizedKeys.keys = [
    (import ../aspect/ssh-pubkeys.nix).diwangsPiv
  ];
  security.sudo.wheelNeedsPassword = false;
}
