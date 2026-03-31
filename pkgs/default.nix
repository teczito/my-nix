# Custom packages, that can be defined similarly to ones from nixpkgs
# You can build them using 'nix build .#example'
pkgs: {
  my-saleae-logic-2 = pkgs.callPackage ./saleae-logic-2 { };
}