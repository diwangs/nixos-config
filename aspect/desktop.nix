{ pkgs, lib, ... }: {
  # Enable the GNOME DM and DE.
  services.displayManager.gdm.enable = true;
  services.desktopManager.gnome.enable = true;
  environment.gnome.excludePackages = with pkgs; [
    # seahorse
    epiphany # Web browser
  ];

  # For Chromium-based program to use Wayland natively instead of XWayland
  # NOTE: this cause bugs, but so far it's bearable
  environment.sessionVariables.NIXOS_OZONE_WL = "1";

  # Enable the X11 windowing system.
  # services.xserver.enable = true;
  services.gvfs.enable = true;
  services.udev.packages = [ pkgs.gnome-settings-daemon ];

  # Fonts: nerd-fonts
  fonts.packages = builtins.filter lib.attrsets.isDerivation (
    builtins.attrValues pkgs.nerd-fonts
  );
}
