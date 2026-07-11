{
	description = "NixOS configuration for paladin-iii";

	inputs = {
 		# nixos-hardware
		nixos-hardware.url = "https://flakehub.com/f/NixOS/nixos-hardware/*";
		
		# NixOS official package source
		# nixpkgs.url = "https://flakehub.com/f/NixOS/nixpkgs/=0.1.985613";
		nixpkgs.url = "https://flakehub.com/f/NixOS/nixpkgs/0.1";
		nixpkgs-stable.url = "https://flakehub.com/f/NixOS/nixpkgs/0.2605"; # Latest stable
		
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
      inputs.nixpkgs.follows = "home-manager";	# vscode is defined by hm
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

		# Private secrets (eval-time toml + runtime .age), pinned like any input.
		# After every edit in the secrets repo: `nix flake update agenix-secrets`.
		# TODO: after moving the dir out and pushing, switch the URL to
		# "git+ssh://git@github.com/diwangs/agenix-secrets.git"
		agenix-secrets.url = "path:/home/diwangs/Codes/agenix-secrets";
	};

	outputs = { 
		self, 
		nixos-hardware, 
		nixpkgs, 
		nixpkgs-stable, 
		home-manager, 
		nix-flatpak, 
		nix-vscode-extensions,
		cua,
		agenix,
		agenix-secrets,
		...
	}: {
		# nixos-rebuild switch --flake path#hostname
		nixosConfigurations.paladin-iii = nixpkgs.lib.nixosSystem rec {
			system = "x86_64-linux";
			# For nixos, but also passed to HM
			specialArgs = rec {
				inherit self;
				inherit cua;
				inherit agenix; # for the CLI package in aspect/secret.nix
				inherit agenix-secrets; # .age file paths in aspect/secret.nix

				# Self-defined args to pass allowed unfree packages
				allowedUnfree = [
					"codeql"
					"claude-code"
					"claude-desktop"

					# VSCode and some unfree extensions
					"vscode"
					"vscode-extension-anthropic-claude-code"
					"vscode-extension-ms-vscode-remote-remote-ssh"

					# AppImages
					"trezor-suite"
					"wootility"
				];

				# Eval-time secrets (TOML), from the private agenix-secrets input
				secrets = agenix-secrets.lib.toml;

				# Modify `allowUnfreePredicate` of `pkgs-stable`
				# We don't similarly modify `pkgs` here to retain the ability of 
				# setting `nixpkgs.overlays` on modules. Instead, set any overlays and
				# config on ./system/nixos.nix.
				pkgs-stable = import nixpkgs-stable {
					inherit system;
					config.allowUnfreePredicate = pkg: (
						builtins.elem (nixpkgs-stable.lib.getName pkg) allowedUnfree # rec
					); 
				};

				# NOTE: each user in home-manager has its own `nixpkgs` instance, but 
				# uses the global `pkgs`. So, define pkgs-modifying overlays on nixos 
				# even if it is used on home-manager, for consistency.
      };
			modules = [
				# Hardware (not portable)
				nixos-hardware.nixosModules.framework-13-7040-amd
				./hardware/hardware-configuration.nix

				# System (packages included)
				# agenix (secrets configured in system/aspect/secret.nix)
				agenix.nixosModules.default
				./system/nixos.nix

				# Home Manager (packages included)
				home-manager.nixosModules.home-manager {
					# To use `pkgs` derived from nixos `nixpkgs` instead of hm specific
					home-manager.useGlobalPkgs = true;
					# To install packages in /etc/profiles
					home-manager.useUserPackages = true;	
					home-manager.backupFileExtension = "bak";
					home-manager.extraSpecialArgs = specialArgs; # rec
					# Home packages are imported inside `system/home-manager.nix`
					home-manager.users.diwangs = import ./system/home-manager.nix;
				}

				# Flatpak (packages included)
				nix-flatpak.nixosModules.nix-flatpak
				./system/flatpak.nix

				# trycua computer-use driver. Enabled in nixos.nix.
				cua.nixosModules.cua-driver
			];
		};
	};
}