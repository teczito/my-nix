{ pkgs, ... }:

# The Ubuntu look for the niri session: Yaru (GTK theme, icons and cursor) with
# niri's blue as the accent, and Ubuntu Sans everywhere. The niri side --
# shadows, corners, the cursor -- is in config-files/niri/config.kdl; the bar is
# config-files/waybar/style.css. Fonts are system-wide, in
# modules/desktop/fonts.nix.
{
  home-manager.users.ruben = {
    home.pointerCursor = {
      enable = true;
      name = "Yaru";
      package = pkgs.yaru-theme;
      size = 24;
      gtk.enable = true;
    };

    gtk = {
      enable = true;
      theme = {
        name = "Yaru-blue-dark";
        package = pkgs.yaru-theme;
      };
      iconTheme = {
        name = "Yaru-blue-dark";
        package = pkgs.yaru-theme;
      };
      font = {
        name = "Ubuntu Sans";
        size = 11;
      };
      # libadwaita (GTK4) apps ignore gtk-theme; they follow color-scheme and
      # accent-color below, which reach them through the gnome portal's
      # Settings interface.
      gtk4.theme = null;
    };

    dconf.settings."org/gnome/desktop/interface" = {
      color-scheme = "prefer-dark";
      accent-color = "blue";
      gtk-theme = "Yaru-blue-dark";
      icon-theme = "Yaru-blue-dark";
      cursor-theme = "Yaru";
      font-name = "Ubuntu Sans 11";
      document-font-name = "Ubuntu Sans 11";
      monospace-font-name = "Ubuntu Sans Mono 13";
    };

    # Qt apps follow the GTK theme instead of rendering as plain Fusion.
    qt = {
      enable = true;
      platformTheme.name = "gtk3";
    };
  };
}
