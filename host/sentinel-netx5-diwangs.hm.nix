{
  config,
  lib,
  os-secret,
  ...
}:
let
  ageIdentityCredential =
    os-secret.systemd-creds.sentinel-netx5-diwangs.ageIdentity;
in
{
  home.username = "diwangs";
  home.homeDirectory = "/home/diwangs";
  home.uid = 1000;
  home.stateVersion = "25.05";
  home.sessionVariables.DOCKER_HOST = "unix:///run/user/${toString config.home.uid}/podman/podman.sock";

  # User-scoped credential: encrypt with --uid=diwangs --with-key=host+tpm2.
  age.enable = true;
  age.secrets."token/access-nova.json".file = os-secret.token."access-nova.json";
  age.identityPaths = lib.mkForce [
    "/run/user/${toString config.home.uid}/credentials/agenix.service/age-identity"
  ];
  systemd.user.services.agenix.Service.SetCredentialEncrypted =
    ageIdentityCredential;

  # ECS-server mode rejects terminal prompts even for profiles without MFA.
  home.sessionVariables.AWS_VAULT_PROMPT = "ykman";

  assertions = [
    {
      assertion = lib.hasPrefix "age-identity:" ageIdentityCredential;
      message = "sentinel-netx5-diwangs's credential must be named age-identity";
    }
  ];
}
