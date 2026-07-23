{ pkgs, ... }: {
  environment.shells = [ pkgs.zsh ]; # Make the login shell visible to GDM.
  users.users.diwangs = {
    shell = pkgs.zsh; # Set default shell; further config goes to home-manager
    ignoreShellProgramCheck = true; # otherwise nix will complain
  };
}
