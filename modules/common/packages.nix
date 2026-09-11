{ pkgs, ... }:

{
  environment.variables = {
    EDITOR = "vim";
  };

  environment.pathsToLink = [ "/libexec" ]; # links /libexec from derivations to /run/current-system/sw

  # Wanted on every host. Graphical ones live in modules/desktop/apps.nix,
  # bench-hardware ones in modules/services/devices.nix. To search, run:
  # $ nix search wget
  environment.systemPackages = with pkgs; [
    direnv
    git
    mc
    nixfmt
    screen
    unzip
    wget
    zip
  ];
}
