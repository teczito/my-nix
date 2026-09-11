{ pkgs, ... }:

{
  xdg.portal.enable = true;
  xdg.portal.wlr.enable = true; # important
  xdg.portal.extraPortals = with pkgs; [
    xdg-desktop-portal-gtk
    xdg-desktop-portal-wlr
  ];
}
