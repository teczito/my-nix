{ ... }:

{
  # Set your time zone.
  time.timeZone = "Europe/Stockholm";

  # Select internationalisation properties.
  i18n.defaultLocale = "en_US.UTF-8";

  i18n.extraLocaleSettings = {
    LC_ADDRESS = "sv_SE.UTF-8";
    LC_IDENTIFICATION = "sv_SE.UTF-8";
    LC_MEASUREMENT = "sv_SE.UTF-8";
    LC_MONETARY = "sv_SE.UTF-8";
    LC_NAME = "sv_SE.UTF-8";
    LC_NUMERIC = "sv_SE.UTF-8";
    LC_PAPER = "sv_SE.UTF-8";
    LC_TELEPHONE = "sv_SE.UTF-8";
    LC_TIME = "sv_SE.UTF-8";
  };

  # The console keymap is derived from the X keyboard configuration, which is
  # why services.xserver.xkb lives here rather than with the rest of the X
  # settings: console.useXkbConfig reads these options directly, whether or not
  # an X server is enabled -- or, on a host without one, even installed.
  console.useXkbConfig = true;
  services.xserver.xkb.layout = "us,se";
  services.xserver.xkb.variant = "euro,";
  services.xserver.xkb.options = "grp:ctrls_toggle";
}
