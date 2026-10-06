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
    defaultSession = "niri";
  };

  # greetd replaces lightdm, for sequencing rather than taste. lightdm starts
  # the new session's compositor *before* it begins tearing the greeter down:
  # on 2026-09-04 the compositor (Hyprland, then) was up at 06:55:36.03 while
  # SIGTERM only reached session-c1.scope at 06:55:36.86, and the greeter then
  # ignored it for the full 90 s. The compositor therefore enumerates input
  # while the greeter still owns seat0, logind hands it revoked fds, and
  # libinput drops the devices -- a session that looks frozen but is only deaf.
  # greetd is a sequential state machine: the greeter exits before the session
  # starts, so that overlap cannot happen. Full diagnosis in CLAUDE.md.
  services.greetd = {
    enable = true;
    # tuigreet draws a TUI; this stops systemd writing boot messages over it
    # (it sets StandardInput/TTYPath/TTYVHangup on the unit).
    useTextGreeter = true;
    settings.default_session.command =
      # niri ships a single session entry (niri.desktop -> niri-session), so
      # tuigreet gets sessionData as-is. The filtered copy that used to sit here
      # existed only to hide Hyprland's non-uwsm hyprland.desktop.
      lib.concatStringsSep " " [
        "${pkgs.tuigreet}/bin/tuigreet"
        "--time"
        "--remember"
        "--remember-session"
        # Echo the password as asterisks instead of showing nothing at all.
        # tuigreet's default redaction character is already "*"; pass
        # --asterisks-char to change it.
        "--asterisks"
        "--sessions ${config.services.displayManager.sessionData.desktops}/share/wayland-sessions"
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
