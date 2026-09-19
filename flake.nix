{
  description = "Ruben's NixOs Flake";

  # the source of my packages
  inputs = {
    # normal nix stuff
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    nixd.url = "github:nix-community/nixd";
    # home-manager stuff
    home-manager.url = "github:nix-community/home-manager";

    # the family meal planner. Private repo, so ssh rather than github: --
    # nix fetches it with the same key this machine already clones it with.
    meal-planner.url = "git+ssh://git@github.com/teczito/meal-planner";
    meal-planner.inputs.nixpkgs.follows = "nixpkgs";

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

      # One host per directory under ./hosts. The host's own default.nix is the
      # only place that decides what that machine is; everything it opts into
      # lives in ./modules and ./users and is imported from there.
      mkHost =
        hostName:
        nixpkgs.lib.nixosSystem {
          inherit system;
          # Flake inputs reach the host's modules through here, so a module
          # file can import what an input provides -- see
          # modules/services/meal-planner.nix.
          specialArgs = { inherit inputs; };
          # modules to use
          modules = [
            { networking.hostName = hostName; }

            (
              { config, pkgs, ... }:
              {
                nixpkgs.overlays = import ./overlays { inherit inputs; };
              }
            )

            ./users
            ./hosts/${hostName}

            home-manager.nixosModules.home-manager # make home manager available to the host config
            {
              # use system-level nixpkgs rather than the HM private ones
              # "This saves an extra Nixpkgs evaluation, adds consistency, and removes the dependency on NIX_PATH, which is otherwise used for importing Nixpkgs."
              home-manager.useGlobalPkgs = true;
            }
          ];
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
          pkgs.nixfmt
        ];
      };

      nixosConfigurations = {
        zbook = mkHost "zbook";
        server = mkHost "server";
      };
    };
}
