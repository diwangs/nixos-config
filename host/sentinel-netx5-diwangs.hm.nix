{ config, ... }:
{
  home.username = "diwangs";
  home.homeDirectory = "/home/diwangs";
  home.uid = 1000;
  home.stateVersion = "25.05";
  home.sessionVariables.DOCKER_HOST = "unix:///run/user/${toString config.home.uid}/podman/podman.sock";
}
