{
  description = "Ruben's NixOs Flake";

  # the source of my packages
  inputs = {
    # normal nix stuff
    nixpkgs.url = "github:NixOS/nixpkgs/master";
    nixd.url = "github:nix-community/nixd";
    # home-manager stuff
    home-manager.url = "github:nix-community/home-manager";

    # use the version of nixpkgs we specified above rather than the one HM would ordinarily use
    home-manager.inputs.nixpkgs.follows = "nixpkgs";
  };

  # what will be produced (i.e. the build)
  outputs = { nixpkgs, nixd, home-manager, ... }: {
    # define a "nixos" build
    nixosConfigurations.nixos = nixpkgs.lib.nixosSystem {
      # system to build for
      system = "x86_64-linux";
      # modules to use
      modules = [
        ./users
        ./apps
        ./configuration.nix # our previous config file

        {
          nixpkgs.overlays = [ nixd.overlays.default ];
          environment.systemPackages = with nixpkgs;[
            nixd
          ];
        }

        home-manager.nixosModules.home-manager # make home manager available to configuration.nix
        {
          # use system-level nixpkgs rather than the HM private ones
          # "This saves an extra Nixpkgs evaluation, adds consistency, and removes the dependency on NIX_PATH, which is otherwise used for importing Nixpkgs."
          home-manager.useGlobalPkgs = true;
        }
      ];
    };
  };
}
