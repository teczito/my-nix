{
  config,
  pkgs,
  lib,
  ...
}:

{
  services.displayManager = {
    # Keep this enabled even though greetd is the login manager: this module
    # owns services.displayManager.sessionData, which collects the xsessions/
    # and wayland-sessions/ .desktop files tuigreet is pointed at below. Its
    # whole config block is `mkIf cfg.enable`, so switching it off would leave
    # tuigreet with no sessions to offer.
    enable = true;
    # greetd does not read this -- tuigreet's --remember-session does that job
    # -- but sessionData.autologinSession is derived from it and an assertion
    # requires it to name a real session, so keep it accurate.
    defaultSession = "hyprland-uwsm";
  };

  # greetd replaces lightdm, for sequencing rather than taste. lightdm starts
  # the new session's compositor *before* it begins tearing the greeter down:
  # on 2026-09-04 Hyprland was up at 06:55:36.03 while SIGTERM only reached
  # session-c1.scope at 06:55:36.86, and the greeter then ignored it for the
  # full 90 s. The compositor therefore enumerates input while the greeter
  # still owns seat0, logind hands it revoked fds, and libinput drops the
  # devices -- a session that looks frozen but is only deaf. greetd is a
  # sequential state machine: the greeter exits before the session starts, so
  # that overlap cannot happen. Full diagnosis in CLAUDE.md.
  services.greetd = {
    enable = true;
    # tuigreet draws a TUI; this stops systemd writing boot messages over it
    # (it sets StandardInput/TTYPath/TTYVHangup on the unit).
    useTextGreeter = true;
    settings.default_session.command =
      let
        # The hyprland package registers *two* wayland sessions, and only one
        # of them goes through uwsm:
        #
        #   hyprland.desktop       Exec=.../bin/start-hyprland
        #   hyprland-uwsm.desktop  Exec=.../bin/uwsm start -e -D Hyprland hyprland.desktop
        #
        # start-hyprland is not a uwsm shim. It is a small fork/waitpid
        # watchdog that execs `Hyprland --watchdog-fd N` directly -- `strings`
        # on the binary contains no "uwsm" at all. So picking "Hyprland"
        # instead of "Hyprland (uwsm-managed)" runs the compositor as a bare
        # process in session-N.scope, and everything uwsm is responsible for
        # silently does not happen:
        #
        #  - graphical-session.target is never reached, so every user unit
        #    bound to it stays dead. elephant.service is one of them, which is
        #    why Mod+P / Mod+R then open a walker stuck on "waiting for
        #    elephant" (see services.elephant.enable in ./hyprland.nix).
        #  - config-files/uwsm/env-hyprland is never sourced, so
        #    AQ_DRM_DEVICES=/dev/dri/igpu is not exported and aquamarine
        #    chooses a DRM device on its own (see
        #    modules/hardware/nvidia-prime.nix).
        #
        # Nothing in programs.hyprland drops the non-uwsm entry -- withUWSM
        # only sets programs.uwsm.enable, while sessionPackages picks up both
        # .desktop files from the package -- so drop it here. The greeter must
        # not be able to offer a session that boots into that state. lightdm
        # hid this only because it was pointed at the uwsm entry.
        sessions = pkgs.runCommand "greetd-sessions" { } ''
          mkdir -p $out
          cp -rL ${config.services.displayManager.sessionData.desktops}/share/. $out/
          chmod -R u+w $out
          rm $out/wayland-sessions/hyprland.desktop
        '';
      in
      lib.concatStringsSep " " [
        "${pkgs.tuigreet}/bin/tuigreet"
        "--time"
        "--remember"
        "--remember-session"
        # Echo the password as asterisks instead of showing nothing at all.
        # tuigreet's default redaction character is already "*"; pass
        # --asterisks-char to change it.
        "--asterisks"
        "--sessions ${sessions}/wayland-sessions"
      ];
  };

  # gnome-keyring was enabled only as a side effect of the GNOME desktop
  # module (services/desktop-managers/gnome.nix), which is gone now. The
  # keyring is not GNOME-specific and login really was unlocking it
  # ("gkr-pam: gnome-keyring-daemon started properly and unlocked keyring"),
  # so enable it directly. This also puts pam_gnome_keyring into the `login`
  # PAM stanza, which is what greetd's own stanza delegates to (it sets
  # useDefaultRules = false and is just `auth substack login`), so the unlock
  # keeps working without a greetd-specific enableGnomeKeyring -- that option
  # is inert here precisely because of useDefaultRules = false.
  services.gnome.gnome-keyring.enable = true;
}
