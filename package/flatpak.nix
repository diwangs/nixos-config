# Flatpak packages: synchronized in cloud, or official version of packages that
# supposed to be in home-manager

{ lib, ... }: {
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

    overrides =
      lib.recursiveUpdate
        (lib.listToAttrs (
          map
            (pkg: {
              name = pkg;
              value = {
                Context.sockets = [
                  "wayland"
                  "x11"
                ];
              };
            })
            [
              # Packages that need X11 socket (not fallback-x11) to open
              "com.bitwarden.desktop"
              "com.valvesoftware.Steam"
              # "com.spotify.Client" # Works, but ugly border

              "com.discordapp.Discord"
              "us.zoom.Zoom"
            ]
        ))
        {
          # Misc specific overrides
          "im.riot.Riot" = {
            # Permission to check power state
            "System Bus Policy"."org.freedesktop.UPower" = "talk";

            # Permission to reach the secret service (oo7)
            "Session Bus Policy"."org.freedesktop.secrets" = "talk";
          };
        };
  };
}
