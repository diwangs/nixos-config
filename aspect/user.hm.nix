{ config, lib, ... }:
let
  # Set per user in host/*.hm.nix, e.g. "key::ssh-ed25519 AAAA..."
  signingKey = config.programs.git.signing.key;
in
{
  # Use SSH key in `yubikey-agent` to sign git commits
  xdg.configFile."git/allowed_signers" = lib.mkIf (signingKey != null) {
    text = "* ${lib.removePrefix "key::" signingKey}\n";
  };
  programs.git = {
    signing = {
      # SSH-based signing via the YubiKey PIV key served by yubikey-agent
      # (ssh-keygen -Y sign goes through SSH_AUTH_SOCK; pinentry per session)
      format = "ssh";
    };
    settings = {
      # Lets `git log --show-signature` verify our own signatures
      gpg.ssh.allowedSignersFile = "${config.xdg.configHome}/git/allowed_signers";
    };
  };
}
