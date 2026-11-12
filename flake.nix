{
  description = "diwangs' NixOS and Home Manager config for various machines";

  inputs = {
    # Private secrets (eval-time toml + runtime .age), pinned like any input.
    # After every edit in the secrets repo: `nix flake update os-secret`.
    os-secret.url = "git+ssh://git@github.com/diwangs/os-secret.git";

    # nixos-hardware
    nixos-hardware.url = "https://flakehub.com/f/NixOS/nixos-hardware/*";

    # Secure Boot
    lanzaboote = {
      url = "github:nix-community/lanzaboote/v1.2.0"; # includeFirmwareBuiltinKeys (Framework)
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # NixOS official package source
    # nixpkgs.url = "https://flakehub.com/f/NixOS/nixpkgs/=0.1.985613";
    nixpkgs.url = "https://flakehub.com/f/NixOS/nixpkgs/0.1";
    nixpkgs-stable.url = "https://flakehub.com/f/NixOS/nixpkgs/0.2605"; # Latest stable

    # Home manager
    home-manager = {
      url = "https://flakehub.com/f/nix-community/home-manager/0.1"; # master, follows unstable
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Encrypted secrets, decrypted at activation time (runtime-only; eval-time
    # values stay in secret.toml). Editing identity: YubiKey PIV P-256 via
    # age-plugin-yubikey. Machine identity: /nix/secret/host.key.
    agenix = {
      url = "github:ryantm/agenix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Declarative encrypted VM images and ephemeral-root persistence.
    disko = {
      url = "github:nix-community/disko";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    impermanence = {
      url = "github:nix-community/impermanence";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.home-manager.follows = "home-manager";
    };

    # Flatpak
    nix-flatpak.url = "https://flakehub.com/f/gmodena/nix-flatpak/*";

    # nix-vscode-extensions
    # nix-vscode-extensions = {
    #   url = "github:nix-community/nix-vscode-extensions/master";
    #   inputs.nixpkgs.follows = "home-manager"; # vscode is defined by hm
    # };

    # nix-zed-extensions: Nix-built (not auto-downloaded) Zed extensions
    nix-zed-extensions = {
      url = "github:DuskSystems/nix-zed-extensions";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Official Hermes Desktop package.
    hermes-agent = {
      url = "github:NousResearch/hermes-agent/v0.23.0";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.home-manager.follows = "home-manager";
    };

    # trycua's computer-use driver flake (package + nixosModule).
    # Follow nixpkgs-stable (also 26.05) so the driver is built against the
    # same baseline upstream tests, without a duplicate nixpkgs in the closure.
    cua = {
      url = "github:trycua/cua/cua-driver-rs-v0.7.0";
      inputs.nixpkgs.follows = "nixpkgs-stable";
    };

    # Repository formatting
    treefmt-nix = {
      url = "https://flakehub.com/f/numtide/treefmt-nix/0.1";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    {
      self,
      os-secret,
      nixos-hardware,
      lanzaboote,
      nixpkgs,
      nixpkgs-stable,
      home-manager,
      agenix,
      disko,
      impermanence,
      nix-flatpak,
      nix-zed-extensions,
      hermes-agent,
      cua,
      treefmt-nix,
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
        "claude-science"
        "claude-science-unwrapped"
        "chatgpt"

        # AppImages
        "trezor-suite"
        "wootility"
      ];
    in
    {
      formatter.${system} = treefmtEval.config.build.wrapper;
      checks.${system} = {
        nixfmt = treefmtEval.config.build.check self;
      };

      # `paladin-iii`: bare-metal laptop
      nixosConfigurations.paladin-iii = nixpkgs.lib.nixosSystem rec {
        inherit system;
        # For nixos, but also passed to HM
        specialArgs = {
          inherit self;
          inherit cua;
          inherit nix-zed-extensions;
          inherit agenix; # for the CLI package in aspect/secret.nix
          inherit os-secret; # .age file paths in aspect/secret.nix
          inherit lanzaboote;
          inherit impermanence;
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
          ./nixos.nix # Portable configs
          ./host/paladin-iii.nix # Host-specific config (not portable)

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
                ./home-manager.nix # Portable (desktop)
                ./host/paladin-iii-diwangs.hm.nix # User-specific
              ];
            };
          }
        ];
      };

      # `sentinel-netx5`: lab's Proxmox VM
      # One instance output: first installs unsigned and generates keys into
      # /run, then uses the os-secret bundle for all later signed generations.
      nixosConfigurations.sentinel-netx5 = nixpkgs.lib.nixosSystem {
        inherit system;
        specialArgs = {
          inherit
            disko
            impermanence
            allowedUnfree
            os-secret
            agenix
            lanzaboote
            ;
        };
        modules = [
          ./nixos.headless.nix
          ./host/sentinel-netx5.nix
          home-manager.nixosModules.home-manager
          {
            home-manager.useGlobalPkgs = true;
            home-manager.useUserPackages = true;
            home-manager.backupFileExtension = "bak";
            home-manager.extraSpecialArgs = {
              inherit
                agenix
                os-secret
                allowedUnfree
                self
                ;
            };
            home-manager.users.diwangs.imports = [
              ./host/sentinel-netx5-diwangs.hm.nix
            ];
          }
        ];
      };

      # Managed hosts, keyed by username only: hostnames (AWS private-IP
      # derived, or Skipjack's login/compute nodes) aren't committed, so
      # home-manager's default `$USER@$HOST` lookup falls through to
      # `homeConfigurations.$USER`. Workflow on a host:
      #   git clone git@github.com:diwangs/nixos-config.git ~/.config/home-manager
      #   home-manager switch
      # Adding a host = one entry below plus its host module.
      homeConfigurations =
        let
          # Standalone HM has no NixOS `pkgs` to share, so mirror the overlay
          # and unfree list that nixos.headless.nix sets on NixOS hosts.
          pkgs = import nixpkgs {
            inherit system;
            overlays = [
              (import ./package/overlay/landstrip/overlay.nix)
            ];
            config.allowUnfreePredicate =
              pkg: builtins.elem (nixpkgs.lib.getName pkg) allowedUnfree;
          };
          # No laptop-only args here (`pkgs-stable`, `nix-zed-extensions`, ...):
          # headless modules must not reference them.
          extraSpecialArgs = {
            inherit
              self
              allowedUnfree
              agenix
              os-secret
              ;
          };
        in
        {
          # `sentinel-skipjack`: JHU-managed linux cluster
          ssangdi1 = home-manager.lib.homeManagerConfiguration {
            inherit pkgs extraSpecialArgs;
            modules = [
              ./home-manager.headless.nix # Shared
              ./host/sentinel-skipjack-ssangdi1.hm.nix # Host-specific
            ];
          };

          # `nova-devbox`: AWS devbox
          admin = home-manager.lib.homeManagerConfiguration {
            inherit pkgs extraSpecialArgs;
            modules = [
              ./home-manager.headless.nix # Shared
              ./host/nova-devbox-admin.hm.nix # Host-specific
            ];
          };
        };
    };
}
