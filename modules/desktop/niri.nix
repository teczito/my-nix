{ lib, pkgs, ... }:

# niri is the only session, on every host that imports ../desktop.
#
# The config is config-files/niri/config.kdl, reached through the
# ~/.config/niri -> /etc/nixos/config-files/niri symlink like the others. It
# pins rendering to /dev/dri/igpu and ignores /dev/dri/dgpu, both udev
# symlinks from modules/hardware/nvidia-prime.nix. On a host without that
# module (the server) neither path exists, and niri just logs a warning and
# picks the GPU itself (primary_node_from_config returns None and it falls
# back to udev's primary GPU) -- so the one shared config is safe everywhere.
{
  # Adds niri.desktop to the session list tuigreet offers (./greetd.nix). Its
  # Exec is niri-session, which runs the compositor as the niri.service user
  # unit; that unit binds graphical-session.target, so waybar.service and
  # elephant.service below start with the session. No uwsm is involved.
  programs.niri.enable = true;

  # niri-session imports the login environment with a bare
  # `systemctl --user import-environment`, and systemd 261 prints
  #   Calling import-environment without a list of variable names is deprecated.
  # to the greeter's TTY on every login. It is also a real hazard: once systemd
  # drops the no-argument form, the session starts without the login
  # environment. Swap in a copy of the script that names every variable
  # explicitly -- the same awk niri's own dinit branch uses -- instead.
  #
  # Only bin/niri-session is replaced, so niri itself is not rebuilt: niri.desktop
  # execs `niri-session` by bare name through PATH, and niri.service runs the
  # original package's bin/niri directly.
  programs.niri.package = pkgs.symlinkJoin {
    name = "niri-${pkgs.niri.version}";
    paths = [ pkgs.niri ];
    inherit (pkgs.niri) passthru meta;
    postBuild = ''
      rm $out/bin/niri-session
      substitute ${pkgs.niri}/bin/niri-session $out/bin/niri-session \
        --replace-fail \
          'systemctl --user import-environment' \
          'systemctl --user import-environment $(awk '"'"'BEGIN{for(v in ENVIRON) if (v != "AWKPATH" && v != "AWKLIBPATH") print v}'"'"')'
      chmod +x $out/bin/niri-session
    '';
  };

  # FileChooser through xdg-desktop-portal-gtk instead of registering Nautilus
  # on D-Bus; thunar is the file manager here. The GNOME portal itself is still
  # added by the module -- niri needs it for screencasting.
  programs.niri.useNautilus = false;

  # niri has no built-in XWayland; it spawns xwayland-satellite on demand when
  # the binary is on PATH. KiCad and the other X11 clients need it. The package
  # carries its own store path to Xwayland, so programs.xwayland is not needed.
  environment.systemPackages = [ pkgs.xwayland-satellite ];

  # The package ships waybar.service, WantedBy=graphical-session.target, so the
  # bar starts with the session. Do not also `spawn-at-startup "waybar"` in
  # config.kdl -- that stacks a second bar on top of the unit's.
  programs.waybar.enable = true;

  # walker 2.x is only a frontend: it talks to the elephant daemon over
  # $XDG_RUNTIME_DIR/elephant/elephant.sock and gets every provider (runner,
  # desktopapplications, calc, ...) from it. With no elephant running, walker
  # starts, fails to connect and exits without ever mapping a surface -- the
  # Mod+P / Mod+R binds fire but nothing appears and nothing is logged. This
  # module ships the systemd user unit, WantedBy=graphical-session.target.
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
  # (The niri module does the same for niri.service, via enableDefaultPath.)
  #
  # elephant's own wrapper prefixes (fd, libqalculate, wl-clipboard, ...) are
  # unaffected: the wrapper prepends them to whatever PATH it inherits.
  systemd.user.services.elephant.environment.PATH = lib.mkForce null;
}
