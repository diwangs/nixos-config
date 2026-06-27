# Edit this configuration file to define what should be installed on
# your system. Help is available in the configuration.nix(5) man page, on
# https://search.nixos.org/options and in the NixOS manual (`nixos-help`).

{ self, config, lib, pkgs, allowedUnfree, ... }: {
	imports = [
		./aspect/audio.nix
		./aspect/locale.nix
		./aspect/network.nix
		./aspect/performance.nix
		./aspect/power.nix
		./aspect/security.nix
		./aspect/users.nix
		./aspect/desktop.nix
		./aspect/key-management.nix

		../package/nixos.nix
	];

	nixpkgs.overlays = let
		# mul31: Java String.hashCode-style hash (seed 0, ×31 per char, kept as
		# uint32). Claude Desktop's growthbook seed map keys flags by this hash
		# of the flag name, not the name itself. Computing it here lets the
		# third patch reference the stable flag NAME instead of a magic number,
		# and stays correct as long as the hash algorithm doesn't change.
		# Verified against known pairs: yukon_silver=574905726,
		# yukon_silver_thinking=1658632017, model_selector_enabled=4108768567.
		mul31 = name: builtins.foldl'
			(acc: c: lib.mod (acc * 31 + lib.strings.charToInt c) 4294967296)
			0
			(lib.stringToCharacters name);
	in [
		self.inputs.nix-vscode-extensions.overlays.default
		self.inputs.claude-desktop.overlays.default

		# Claude Desktop 3p (OpenRouter) additional overlays
		#
		# Problem: OpenRouter has a different model ID than Anthropic 1p. This
		# 	caused problems, particularly when it comes to effort selection, 
		# 	thinking toggle, and 1m context selection across Chat, Cowork, and 
		# 	Code. Therefore, we make these patches:
		#
		# First patch: disable the guard that makes the app exits when remote debug
		# 	port is enabled. This is not directly related to the problem, but a 
		# 	necessary intermediate step to enable dynamic analysis.
		#
		# Second patch: change the normalization regex of the model ID. Claude 
		# 	Desktop could handle non Anthropic 1p model ID, but it only covers 
		#		dot-based syntax used by Bedrock and Vertex, not slash-based syntax
		#		used by OpenRouter. Changing this make Claude Desktop recognizes the 
		# 	model ID and assign the correct capabilities and description.
		#
		# Third patch: enable the `yukon_silver_thinking` feature flag. While the
		#		second patch enables the fable disablement and effort slider in Cowork
		#		and Code, it does not enable the thinking toggle. Setting the right
		#		feature flag in the 3p bootstrap enables this in Cowork. The seed map
		#		keys flags by their `mul31` hash, which we compute from the flag name
		#		via the `mul31` helper above (yukon_silver_thinking -> 1658632017)
		#		rather than hardcoding the number. P.S. `yukonSilver` ~ Cowork's VM
		#
		# Fourth patch: change the `De` value. Chat has an
		#		additional guard to enable effort slider and thinking toggle. Changing
		# 	this guard (which is true for Cowork and Code but false for chat) in
		#		the ion bundle is required to apply the third patch to Chat as well.
		# 
		# TODO: this fourth patch is the least robust since it has a lot of 
		#		minified variables. Find a more robust way to patch this.
		(final: prev: {
			claude-desktop = prev.claude-desktop.overrideAttrs (old: {
				postInstall = (old.postInstall or "") + ''
					asarRoot=$out/lib/claude-desktop/electron/resources
					work=$(mktemp -d)
					asar extract "$asarRoot/app.asar" "$work/contents"

					# First patch: tertiary statement that checks process.argv and exits
					substituteInPlace "$work/contents/.vite/build/index.pre.js" \
						--replace-fail \
							'&&process.exit(1)' \
							'&&void 0'

					# Second patch
					substituteInPlace "$work/contents/.vite/build/index.js" \
						--replace-fail \
							'.replace(/^(?:[a-z][a-z0-9-]*\.)?anthropic\./,"")' \
							'.replace(/^(?:[a-z][a-z0-9-]*[./])?anthropic[./]/,"")' \
						--replace-fail \
							'.replace(/-\d{8}$/,"")}' \
							'.replace(/-\d{8}$/,"").replace(/(\d)\.(\d)/g,"$1-$2")}'

					# Third patch: inject growthbook with mul31 of yukon_silver_thinking
					substituteInPlace "$work/contents/.vite/build/index.js" \
						--replace-fail \
							'return{${toString (mul31 "yukon_silver")}:' \
							'return{"${toString (mul31 "yukon_silver_thinking")}":{defaultValue:!0},${toString (mul31 "yukon_silver")}:'

					# Misc patch: disable thinking for Haiku because it broke title gen
					substituteInPlace "$work/contents/.vite/build/index.js" \
						--replace-fail \
							'NODE_USE_SYSTEM_CA:"1",CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC:"1"}' \
							'NODE_USE_SYSTEM_CA:"1",CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC:"1",MAX_THINKING_TOKENS:"0"}'

					# Repack app.asar only. The existing app.asar.unpacked dir
					# carries files the build adds after the original pack
					# (claude-native stub, cowork daemon) that a fresh --unpack
					# would drop, so leave it untouched.
					asar pack "$work/contents" "$work/app.asar" --unpack '**/*.node'
					cp -f "$work/app.asar" "$asarRoot/app.asar"
					rm -rf "$work"

					# Fourth patch: unlock the thinking/effort toggle on the Chat
					# surface (see the Second-patch comment). The renderer guard
					# `De` is false on Chat (considerEnabledForNonUI = Cowork
					# capability store), so force it true. CDP-confirmed: with
					# this, Chat's model selector shows Effort/thinking like
					# Code/Cowork. The ion bundle is a loose file in the output
					# (not in app.asar), so patch it directly; its filename hash
					# varies per build, hence the glob.
					for ionBundle in "$asarRoot/ion-dist/assets/v1/"index-*.js; do
						substituteInPlace "$ionBundle" \
							--replace-fail \
								'De=xe.considerEnabledForNonUI&&(_&&!ve||Q||j&&G)&&!Y,Pe=Ae&&De&&!J' \
								'De=!0,Pe=Ae&&De&&!J'
					done
				'';
			});
		})
	];

	nix.settings.experimental-features = [ "nix-command" "flakes" ];

	# nix-ld: for packages that hasn't been nixified
  # e.g., `fw-ectool` and virtualhere
  programs.nix-ld.enable = true;
	# programs.nix-ld.libraries = with pkgs; [
	# 	libusb1			# For firmware updates with SuzyQ
	# ];

	security.rtkit.enable = true;

	# Whitelist unfree packages
	# Define here instead of flake.nix to avoid replacing the whole pkgs
	nixpkgs.config.allowUnfreePredicate = pkg: builtins.elem (lib.getName pkg) allowedUnfree;

	# Configure keymap in X11
	# services.xserver.xkb.layout = "us";
	# services.xserver.xkb.options = "eurosign:e,caps:escape";

	# Copy the NixOS configuration file and link it from the resulting system
	# (/run/current-system/configuration.nix). This is useful in case you
	# accidentally delete configuration.nix.
	# system.copySystemConfiguration = true;

	# This option defines the first version of NixOS you have installed on this particular machine,
	# and is used to maintain compatibility with application data (e.g. databases) created on older NixOS versions.
	#
	# Most users should NEVER change this value after the initial install, for any reason,
	# even if you've upgraded your system to a new NixOS release.
	#
	# This value does NOT affect the Nixpkgs version your packages and OS are pulled from,
	# so changing it will NOT upgrade your system.
	#
	# This value being lower than the current NixOS release does NOT mean your system is
	# out of date, out of support, or vulnerable.
	#
	# Do NOT change this value unless you have manually inspected all the changes it would make to your configuration,
	# and migrated your data accordingly.
	#
	# For more information, see `man configuration.nix` or https://nixos.org/manual/nixos/stable/options#opt-system.stateVersion .
	system.stateVersion = "23.11"; # Did you read the comment?
}
