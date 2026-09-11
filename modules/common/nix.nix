{ pkgs, ... }:

{
  nix = {
    package = pkgs.nixVersions.git;
    extraOptions = ''
      experimental-features = nix-command flakes auto-allocate-uids fetch-tree configurable-impure-env
    '';
    settings.trusted-users = [
      "root"
      "@wheel"
    ];
  };

  # Allow unfree packages
  nixpkgs.config.allowUnfree = true;
}
