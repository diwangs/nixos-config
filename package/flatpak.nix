# Flatpak packages: synchronized in cloud, or official version of packages that
# supposed to be in home-manager

{ lib, ... }:
let
  # Apps that need the real X11 socket (not fallback-x11) to open.
  # The global override (nixos.nix) is Wayland-only and drops x11, so re-grant
  # it per-app here. This wins over the global `!x11` for these apps.
  needsX11 = [
    "com.bitwarden.desktop"
    "com.spotify.Client" # Works, but ugly border
    "com.valvesoftware.Steam"

    "com.discordapp.Discord"
    "com.slack.Slack"
    "us.zoom.Zoom"
  ];

  # Apps that need the Secret Service (oo7) instead of the Secret Portal.
  # The global override sets `org.freedesktop.secrets=none`, so re-grant `talk`
  # per-app here.
  needsSecretService = [
    "im.riot.Riot"
  ];

  # Build `{ "<app>" = value; ... }` for every app in `apps`.
  forApps = apps: value: lib.genAttrs apps (_: value);
in
{
  services.flatpak = {
    packages = [
      # Cloud
      "com.bitwarden.desktop" # Official!
      "com.spotify.Client"
      "com.valvesoftware.Steam"

      # Gossip
      "com.discordapp.Discord" # Official!
      "im.riot.Riot"
      "com.slack.Slack"
      "us.zoom.Zoom"
      "org.signal.Signal"

      # Local media (install via flatpak only if official for faster update)
      "app.zen_browser.zen" # Official!
      "com.moonlight_stream.Moonlight" # Official!
      "md.obsidian.Obsidian" # Official!
    ];

    # Per-app overrides, layered additively on top of the Wayland-only global
    # override: each entry re-grants only what that app needs. `recursiveUpdate`
    # is safe here because the categories touch disjoint keys (Context.sockets
    # vs Session Bus Policy), so no leaf list is ever clobbered.
    overrides = lib.foldl' lib.recursiveUpdate { } [
      (forApps needsX11 { Context.sockets = [ "x11" ]; })
      (forApps needsSecretService {
        "Session Bus Policy"."org.freedesktop.secrets" = "talk";
      })

      # Misc one-off policies
      {
        # riot: permission to check power state
        "im.riot.Riot"."System Bus Policy"."org.freedesktop.UPower" = "talk";
      }
    ];
  };
}
