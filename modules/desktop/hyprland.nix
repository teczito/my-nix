{ ... }:

{
  # The hyprland package itself is not listed here: programs.hyprland.enable
  # already does `environment.systemPackages = [ cfg.package ]`.
  programs.hyprland.enable = true;
  programs.hyprland.xwayland.enable = true;
  # Required, not optional. The session actually used here is
  # hyprland-uwsm.desktop, whose Exec is `uwsm start -e -D Hyprland
  # hyprland.desktop`. uwsm needs its own systemd user units
  # (wayland-session-bindpid@, wayland-wm@, ...) to exist; this option is what
  # pulls the uwsm module in and puts them in systemd.packages. Without it uwsm
  # aborts with "Unit wayland-session-bindpid@<pid>.service not found" and the
  # compositor is never exec'd at all -- the session dies straight back to the
  # greeter.
  #
  # It does NOT make the *other* entry, hyprland.desktop, go through uwsm: that
  # one execs start-hyprland, a plain watchdog around Hyprland with no uwsm
  # involvement. services.greetd in ./greetd.nix filters it out of the list
  # tuigreet offers, precisely so it cannot be chosen by accident.
  programs.hyprland.withUWSM = true;
  programs.waybar.enable = true;

  # walker 2.x is only a frontend: it talks to the elephant daemon over
  # $XDG_RUNTIME_DIR/elephant/elephant.sock and gets every provider (runner,
  # desktopapplications, calc, ...) from it. With no elephant running, walker
  # starts, fails to connect and exits without ever mapping a surface -- the
  # Mod+P / Mod+R binds fire and Hyprland logs "[executor] Executing walker",
  # but nothing appears and nothing is logged. This module ships the systemd
  # user unit, which is WantedBy=graphical-session.target -- a target only ever
  # reached when the session is started through uwsm, hence the session
  # filtering in ./greetd.nix.
  services.elephant.enable = true;
}
