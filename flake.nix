{
  description = "Ruben's NixOs Flake";

  # the source of my packages
  inputs = {
    # normal nix stuff
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    nixpkgs-nixos-24-11.url = "github:NixOS/nixpkgs/nixos-24.11";
    nixd.url = "github:nix-community/nixd";
    # home-manager stuff
    home-manager.url = "github:nix-community/home-manager";

    # use the version of nixpkgs we specified above rather than the one HM would ordinarily use
    home-manager.inputs.nixpkgs.follows = "nixpkgs-nixos-24-11";
  };

  # what will be produced (i.e. the build)
  outputs = { nixpkgs, nixpkgs-nixos-24-11, nixd, home-manager, ... }:
    let
      # system to build for
      system = "x86_64-linux";
      overlay-nixos-24-11 = final: prev: {
        nixos-24-11 = nixpkgs-nixos-24-11.legacyPackages.${prev.system};
        # use this variant if unfree packages are needed:
        # unstable = import nixpkgs-unstable {
        #   inherit system;
        #   config.allowUnfree = true;
        # };

      };
    in {
      # define a "nixos" build
      nixosConfigurations.nixos = nixpkgs.lib.nixosSystem {
        inherit system;
        # modules to use
        modules = [
          # Overlays-module makes "pkgs.nixos-24-11" available in modules
          ({ config, pkgs, ... }: {
            nixpkgs.overlays = [ overlay-nixos-24-11 ];
          })

          ./users
          ./apps
          ./configuration.nix # our previous config file

          {
            nixpkgs.overlays = [ nixd.overlays.default ];
            environment.systemPackages = with nixpkgs; [ nixd ];
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
