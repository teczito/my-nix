{
  description = "Ruben's NixOs Flake";

  # the source of my packages
  inputs = {
    # normal nix stuff
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    nixd.url = "github:nix-community/nixd";
    # home-manager stuff
    home-manager.url = "github:nix-community/home-manager";

    # use the version of nixpkgs we specified above rather than the one HM would ordinarily use
    home-manager.inputs.nixpkgs.follows = "nixpkgs";
  };

  # what will be produced (i.e. the build)
  outputs =
    {
      home-manager,
      nixd,
      nixpkgs,
      ...
    }@inputs:
    let
      # system to build for
      system = "x86_64-linux";

      # nixpkgs for the dev shell; claude-code is unfree
      pkgs = import nixpkgs {
        inherit system;
        config.allowUnfree = true;
        overlays = [ nixd.overlays.default ];
      };
    in
    {
      # `nix develop` / `nix develop /etc/nixos`
      devShells.${system}.default = pkgs.mkShell {
        name = "nixos-config";

        # not `with pkgs;` — that would not shadow the `nixd` flake input above
        packages = [
          pkgs.claude-code
          pkgs.nixd
          pkgs.nixfmt-rfc-style
        ];
      };

      # define a "nixos" build
      nixosConfigurations.nixos = nixpkgs.lib.nixosSystem {
        inherit system;
        # modules to use
        modules = [
          (
            { config, pkgs, ... }:
            {
              nixpkgs.overlays = import ./overlays { inherit inputs; };
            }
          )

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
