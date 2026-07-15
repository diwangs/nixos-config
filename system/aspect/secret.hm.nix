{ age-secrets, ... }: {
	# Rootless counterpart to system/aspect/secret.nix's NixOS agenix module:
	# nova-devbox has no root-run activation, so secrets decrypt per-user via
	# agenix's home-manager module (systemd --user, into $XDG_RUNTIME_DIR/agenix)
	# instead of chown-to-user at boot. Its host-specific identity is configured
	# in flake.nix and provisioned outside this configuration.
	age.secrets."token/bedrock".file = age-secrets.token.bedrock;
}
