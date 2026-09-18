{ ... }:

# The graphical-workstation layer for ruben: GUI applications, plus the bench
# tools that only make sense on a machine you sit in front of. A headless host
# imports ./default.nix and stops there.
{
  # For xpdf in home.packages below.
  nixpkgs.config.permittedInsecurePackages = [
    "xpdf-4.06"
  ];

  # adb for android-tools, dialout for USB serial, input for evdev, nm-openvpn
  # for the NetworkManager VPN plugins -- all bench/desk concerns.
  users.users.ruben.extraGroups = [
    "adb"
    "dialout"
    "input"
    "nm-openvpn"
  ];

  home-manager.users.ruben =
    { pkgs, ... }:
    {
      home.packages = with pkgs; [
        # freecad
        git-cola
        iw
        minicom
        # rustdesk
        speedcrunch
        vscode
        xpdf
      ];

      programs.bash.shellAliases = {
        # KiCad upstream does not support the GTK Wayland backend. Under Hyprland
        # it lands on wx's EGL/wl_egl canvas path, where zoom/pan stutters and
        # cursor warping (Preferences > Common > "Center and warp cursor on zoom")
        # silently no-ops. Pin it to XWayland/GLX instead.
        kicad = "GDK_BACKEND=x11 kicad";
      };
    };
}
