{
	description = "NixOS configuration for paladin-iii";

	inputs = {
 		# nixos-hardware
		nixos-hardware.url = "https://flakehub.com/f/NixOS/nixos-hardware/*";
		
		# NixOS official package source
		nixpkgs.url = "https://flakehub.com/f/NixOS/nixpkgs/0.1";
		nixpkgs-stable.url = "https://flakehub.com/f/NixOS/nixpkgs/0.2511"; # Latest stable
		
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
	};

	outputs = { 
		self, 
		nixos-hardware, 
		nixpkgs, 
		nixpkgs-stable, 
		home-manager, 
		nix-flatpak, 
		nix-vscode-extensions, 
		... 
	}: {
		# nixos-rebuild switch --flake path#hostname
		nixosConfigurations.paladin-iii = nixpkgs.lib.nixosSystem rec {
			system = "x86_64-linux";
			specialArgs = rec {
				inherit self;

				# Self-defined args to pass allowed unfree packages
				allowedUnfree = [
					"codeql"
					"github-copilot-cli"

					# VSCode and some unfree extensions
					"vscode"
					"vscode-extension-github-copilot"
					"vscode-extension-github-copilot-chat"
					"vscode-extension-MS-python-vscode-pylance"
					"vscode-extension-ms-vscode-remote-remote-ssh"

					# AppImages
					"trezor-suite"
					"wootility"
				];

				# Secrets from TOML
				secrets = builtins.fromTOML (builtins.readFile ./secret.toml);

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
			];
		};
	};
}