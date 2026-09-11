{ pkgs, ... }:

{
  environment.systemPackages = with pkgs; [
    android-tools
    my-saleae-logic-2
  ];

  # udev rules
  services.udev.packages = [
    pkgs.stlink
    pkgs.my-saleae-logic-2
  ];
  # services.udev.extraRules is a `lines` option, so this merges with the iGPU
  # symlink rule in modules/hardware/nvidia-prime.nix rather than colliding with
  # it. A host importing both gets the union.
  services.udev.extraRules = import ../../config-files/ti/71-ti-permissions.rules;
}
