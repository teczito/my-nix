{ lib, ... }:

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

  # elephant activates a .desktop entry by handing its Exec line to `sh -c`, and
  # 23 of the 27 entries on this host spell that Exec as a bare command name
  # (`thunar %U`, `kitty`, `code`, ...) rather than an absolute store path. So
  # launching anything needs a shell *and* the session's own bin directories on
  # PATH. The unit had neither.
  #
  # NixOS gives every systemd service a default `path` of
  # coreutils/findutils/gnugrep/gnused/systemd and writes it into the unit as an
  # explicit `Environment=PATH=...`. That override *replaces* the PATH the user
  # manager would otherwise have passed down, so elephant ends up with
  # XDG_DATA_DIRS covering the full session -- walker therefore lists every
  # application -- while its PATH holds no `sh` and none of the binaries. Every
  # entry is visible and none of them can start.
  #
  # The failure is silent from the frontend: walker just closes, exactly as if
  # the keybind were broken. The only trace is in the daemon log:
  #
  #   journalctl --user -u elephant -b
  #   ERROR desktopapplications activate=thunar.desktop \
  #     error="exec: \"sh\": executable file not found in $PATH"
  #
  # Setting PATH to null drops the `Environment=PATH=` line entirely, so elephant
  # inherits the systemd user manager's PATH -- /run/wrappers/bin plus the
  # per-user and system profiles -- which is the same PATH an app started from a
  # terminal gets, and where both `sh` and all 23 bare Execs resolve. Do not
  # "fix" this by adding pkgs.bash to `path` instead: that satisfies `sh -c` and
  # leaves all 23 failing one level deeper, as `thunar: command not found`.
  #
  # elephant's own wrapper prefixes (fd, libqalculate, wl-clipboard, ...) are
  # unaffected: the wrapper prepends them to whatever PATH it inherits.
  systemd.user.services.elephant.environment.PATH = lib.mkForce null;
}
