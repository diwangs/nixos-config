{ config, ... }:
let
  # pivSshPubKey = "ecdsa-sha2-nistp256 AAAAE2VjZHNhLXNoYTItbmlzdHAyNTYAAAAIbmlzdHAyNTYAAABBBAlqJuT2Lkccq5Q3Jkc8msxn9FQ1tvtP4i/fvTIpBrjUAB/RayymoXWLQUly3o9ytPcJK1PDI/EuxbdjmxKEaSI=";
  pivSshPubKey = (import ./ssh-pubkeys.nix).diwangsPiv;
in
{
  # Use SSH key in `yubikey-agent` to sign git commits
  xdg.configFile."git/allowed_signers".text = "* ${pivSshPubKey}\n";
  programs.git = {
    signing = {
      # SSH-based signing via the YubiKey PIV key served by yubikey-agent
      # (ssh-keygen -Y sign goes through SSH_AUTH_SOCK; pinentry per session)
      format = "ssh";
      key = "key::${pivSshPubKey}";
    };
    settings = {
      # Lets `git log --show-signature` verify our own signatures
      gpg.ssh.allowedSignersFile = "${config.xdg.configHome}/git/allowed_signers";
    };
  };
}
