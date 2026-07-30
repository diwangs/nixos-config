{ config, ... }:
let
  # pivSshPubKey = "ecdsa-sha2-nistp256 AAAAE2VjZHNhLXNoYTItbmlzdHAyNTYAAAAIbmlzdHAyNTYAAABBBAlqJuT2Lkccq5Q3Jkc8msxn9FQ1tvtP4i/fvTIpBrjUAB/RayymoXWLQUly3o9ytPcJK1PDI/EuxbdjmxKEaSI=";
  pivSshPubKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIN8rN7/MkdOAlx+eovs/7wxAN1Lb9PnaeLESTAm0EB55";
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
