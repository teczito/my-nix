{ pkgs, ... }:

{
  environment.systemPackages = with pkgs; [
    brave
    brightnessctl
    dunst
    grim
    kitty
    networkmanagerapplet
    playerctl
    slurp
    walker
    wl-clipboard
  ];

  programs.dconf.enable = true;
  programs.thunar.enable = true;
}
