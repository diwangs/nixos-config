{ agenix-secrets, ... }: {
	# Rootless counterpart to system/aspect/secret.nix's NixOS agenix module:
	# nova-devbox has no root-run activation, so secrets decrypt per-user via
	# agenix's home-manager module (systemd --user, into $XDG_RUNTIME_DIR/agenix)
	# instead of chown-to-user at boot. Identity is a dedicated age key already
	# provisioned on the box (not managed here, since there's no NixOS module).
	age.identityPaths = [ "/nix/secret/nova-devbox.key" ];
	age.secrets."bedrock-token".file = agenix-secrets.lib.age.bedrock-token;
}
