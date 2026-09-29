{ pkgs, ... }:

# niri as a second, experimental session alongside Hyprland. Not part of
# ./default.nix: a host opts in by importing this file (hosts/zbook does).
#
# The config is config-files/niri/config.kdl, reached through the
# ~/.config/niri -> /etc/nixos/config-files/niri symlink like the others. It
# pins rendering to /dev/dri/igpu and ignores /dev/dri/dgpu, both udev
# symlinks from modules/hardware/nvidia-prime.nix, so it only makes sense on a
# host that imports that module.
{
  # Adds niri.desktop to the session list, which tuigreet picks up through
  # ./greetd.nix's filtered copy of sessionData. Its Exec is niri-session,
  # which runs the compositor as the niri.service user unit; that unit binds
  # graphical-session.target, so waybar.service and elephant.service start
  # exactly as they do under uwsm. No uwsm involvement is needed.
  #
  # The module's mkDefault defaultSession = "niri" loses to the explicit
  # "hyprland-uwsm" in ./greetd.nix, so Hyprland stays the default.
  programs.niri.enable = true;

  # FileChooser through xdg-desktop-portal-gtk instead of registering Nautilus
  # on D-Bus; thunar is the file manager here. The GNOME portal itself is still
  # added by the module -- niri needs it for screencasting.
  programs.niri.useNautilus = false;

  # niri has no built-in XWayland; it spawns xwayland-satellite on demand when
  # the binary is on PATH. KiCad and the other X11 clients need it.
  environment.systemPackages = [ pkgs.xwayland-satellite ];
}
