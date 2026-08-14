{
  description = "diwangs' NixOS and Home Manager config for various machines";

  inputs = {
    # nixos-hardware
    nixos-hardware.url = "https://flakehub.com/f/NixOS/nixos-hardware/*";

    # NixOS official package source
    # nixpkgs.url = "https://flakehub.com/f/NixOS/nixpkgs/=0.1.985613";
    nixpkgs.url = "https://flakehub.com/f/NixOS/nixpkgs/0.1";
    nixpkgs-stable.url = "https://flakehub.com/f/NixOS/nixpkgs/0.2605"; # Latest stable

    # Repository formatting
    treefmt-nix = {
      url = "github:numtide/treefmt-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Home manager
    home-manager = {
      url = "github:nix-community/home-manager"; # master, follows unstable
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Flatpak
    nix-flatpak.url = "https://flakehub.com/f/gmodena/nix-flatpak/*";

    # nix-vscode-extensions
    nix-vscode-extensions = {
      url = "github:nix-community/nix-vscode-extensions/master";
      inputs.nixpkgs.follows = "home-manager"; # vscode is defined by hm
    };

    # nix-zed-extensions: Nix-built (not auto-downloaded) Zed extensions
    nix-zed-extensions = {
      url = "github:DuskSystems/nix-zed-extensions";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # trycua's computer-use driver flake (package + nixosModule).
    # Follow nixpkgs-stable (also 26.05) so the driver is built against the
    # same baseline upstream tests, without a duplicate nixpkgs in the closure.
    cua = {
      url = "github:trycua/cua/cua-driver-rs-v0.7.0";
      inputs.nixpkgs.follows = "nixpkgs-stable";
    };

    # Encrypted secrets, decrypted at activation time (runtime-only; eval-time
    # values stay in secret.toml). Editing identity: YubiKey PIV P-256 via
    # age-plugin-yubikey. Machine identity: /nix/secret/host.key.
    agenix = {
      url = "github:ryantm/agenix";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.home-manager.follows = "home-manager";
      inputs.darwin.follows = ""; # not on macOS, drop the nix-darwin dep
    };

    # Secure Boot
    lanzaboote = {
      # Post-v1.1 revision with Framework firmware-builtin key enrollment.
      url = "github:nix-community/lanzaboote/6183ac79eadb079a1e72fa2c60915601be669100";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Private secrets (eval-time toml + runtime .age), pinned like any input.
    # After every edit in the secrets repo: `nix flake update agenix-secrets`.
    age-secrets.url = "git+ssh://git@github.com/diwangs/age-secrets.git";
  };

  outputs =
    {
      self,
      nixos-hardware,
      nixpkgs,
      nixpkgs-stable,
      treefmt-nix,
      home-manager,
      nix-flatpak,
      nix-zed-extensions,
      cua,
      agenix,
      age-secrets,
      lanzaboote,
      ...
    }:
    let
      system = "x86_64-linux";
      pkgs = nixpkgs.legacyPackages.${system};
      treefmtEval = treefmt-nix.lib.evalModule pkgs {
        projectRootFile = "flake.nix";
        programs.nixfmt = {
          enable = true;
          width = 80;
        };
      };

      # Self-defined args to pass allowed unfree packages (shared by the
      # laptop nixosConfiguration and the devbox homeConfigurations)
      allowedUnfree = [
        "codeql"
        "claude-code"
        "claude-desktop"
        "chatgpt"

        # VSCode and some unfree extensions
        "vscode"
        "vscode-extension-anthropic-claude-code"
        "vscode-extension-ms-vscode-remote-remote-ssh"

        # AppImages
        "trezor-suite"
        "wootility"
      ];
    in
    {
      formatter.${system} = treefmtEval.config.build.wrapper;
      checks.${system}.nixfmt = treefmtEval.config.build.check self;

      # nixos-rebuild switch --flake path#hostname
      nixosConfigurations.paladin-iii = nixpkgs.lib.nixosSystem rec {
        inherit system;
        # For nixos, but also passed to HM
        specialArgs = {
          inherit self;
          inherit cua;
          inherit nix-zed-extensions;
          inherit agenix; # for the CLI package in aspect/secret.nix
          inherit age-secrets; # .age file paths in aspect/secret.nix
          inherit lanzaboote;
          inherit nixos-hardware;
          inherit nix-flatpak;
          inherit allowedUnfree;

          # Modify `allowUnfreePredicate` of `pkgs-stable`
          # We don't similarly modify `pkgs` here to retain the ability of
          # setting `nixpkgs.overlays` on modules. Instead, set any overlays and
          # config on ./nixos.nix.
          pkgs-stable = import nixpkgs-stable {
            inherit system;
            config.allowUnfreePredicate =
              pkg:
              (builtins.elem (nixpkgs-stable.lib.getName pkg) allowedUnfree # rec
              );
          };

          # NOTE: each user in home-manager has its own `nixpkgs` instance, but
          # uses the global `pkgs`. So, define pkgs-modifying overlays on nixos
          # even if it is used on home-manager, for consistency.
        };
        modules = [
          ./host/paladin-iii.nix # Host-specific config (not portable)
          ./nixos.nix # Portable configs

          # Home Manager
          home-manager.nixosModules.home-manager
          {
            # To use `pkgs` derived from nixos `nixpkgs` instead of hm specific
            home-manager.useGlobalPkgs = true;
            # To install packages in /etc/profiles
            home-manager.useUserPackages = true;
            home-manager.backupFileExtension = "bak";
            home-manager.extraSpecialArgs = specialArgs; # rec
            # Home packages and agenix's Home Manager module are imported
            # inside `home-manager.nix`.
            home-manager.users.diwangs = {
              imports = [
                ./host/paladin-iii-diwangs.hm.nix # User-specific
                ./home-manager.nix # Portable (desktop)
              ];
            };
          }
        ];
      };

      # Rootless devbox servers, keyed by username only: hostnames are AWS
      # private-IP-derived and not committed, so home-manager's default
      # `$USER@$HOST` lookup falls through to `homeConfigurations.$USER`.
      # Workflow on a devbox:
      #   git clone git@github.com:diwangs/nixos-config.git ~/.config/home-manager
      #   home-manager switch
      # Adding a devbox user = adding one string to the list below.
      homeConfigurations = nixpkgs.lib.genAttrs [ "admin" ] (
        username:
        home-manager.lib.homeManagerConfiguration {
          pkgs = import nixpkgs {
            inherit system;
            overlays = [
              (import ./package/overlay/landstrip/overlay.nix)
              (import ./package/overlay/codex/overlay.nix)
              (import ./package/overlay/codex-acp/overlay.nix)
            ];
            config.allowUnfreePredicate =
              pkg: builtins.elem (nixpkgs.lib.getName pkg) allowedUnfree;
          };
          # No laptop-only args here (`secrets`, `pkgs-stable`): devbox-reachable
          # modules must not reference them.
          extraSpecialArgs = {
            inherit
              self
              allowedUnfree
              agenix
              age-secrets
              ;
          };
          modules = [
            { home.uid = 1000; }
            ./host/nova-devbox-admin.hm.nix # User-specific
            ./home-manager.devbox.nix # Portable (devbox)
          ];
        }
      );
    };
}
