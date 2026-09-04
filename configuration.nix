# Edit this configuration file to define what should be installed on
# your system.  Help is available in the configuration.nix(5) man page
# and in the NixOS manual (accessible by running ‘nixos-help’).

{
  config,
  pkgs,
  lib,
  ...
}:

{
  imports = [
    # Include the results of the hardware scan.
    ./hardware-configuration.nix
    ./backup-configurations.nix
    ./timer-configuration.nix
    ./nvidia-prime.nix
  ];

  nix = {
    package = pkgs.nixVersions.git;
    extraOptions = ''
      experimental-features = nix-command flakes auto-allocate-uids fetch-tree configurable-impure-env
    '';
  };

  # Bootloader.
  boot.loader.systemd-boot.enable = true;
  boot.loader.timeout = 300;
  boot.loader.efi.canTouchEfiVariables = true;
  boot.loader.efi.efiSysMountPoint = "/boot";

  # The 't'/'T' keys in the systemd-boot menu persist a LoaderConfigTimeout EFI
  # variable, which takes precedence over the timeout written to loader.conf.
  # Ours was left on "menu-force", i.e. show the menu and never time out, so
  # boot.loader.timeout above had no effect. Clearing the variable makes
  # systemd-boot fall back to loader.conf.
  boot.loader.systemd-boot.extraInstallCommands = ''
    ${config.systemd.package}/bin/bootctl set-timeout ""
  '';

  # Kernel version
  boot.kernelPackages = pkgs.linuxPackages_latest;

  networking.hostName = "nixos"; # Define your hostname.
  # networking.wireless.enable = true;  # Enables wireless support via wpa_supplicant.

  # Configure network proxy if necessary
  # networking.proxy.default = "http://user:password@proxy:port/";
  # networking.proxy.noProxy = "127.0.0.1,localhost,internal.domain";

  # Enable networking
  networking.networkmanager.enable = true;

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

  console.useXkbConfig = true;

  # Enable ssh-server (on-demand)
  # run 'sudo systemctl start sshd' to start the server
  services.openssh.enable = true;
  systemd.services.sshd.wantedBy = lib.mkForce [ ];

  # Enable the X11 windowing system.
  services = {
    displayManager = {
      # Keep this enabled even though greetd is the login manager: this module
      # owns services.displayManager.sessionData, which collects the xsessions/
      # and wayland-sessions/ .desktop files tuigreet is pointed at below. Its
      # whole config block is `mkIf cfg.enable`, so switching it off would leave
      # tuigreet with no sessions to offer.
      enable = true;
      # greetd does not read this -- tuigreet's --remember-session does that job
      # -- but sessionData.autologinSession is derived from it and an assertion
      # requires it to name a real session, so keep it accurate.
      defaultSession = "none+awesome";
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
    greetd = {
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
          #    elephant" (see services.elephant.enable below).
          #  - config-files/uwsm/env-hyprland is never sourced, so
          #    AQ_DRM_DEVICES=/dev/dri/igpu is not exported and aquamarine
          #    chooses a DRM device on its own (see ./nvidia-prime.nix).
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
          "--sessions ${sessions}/wayland-sessions"
          # X11 sessions need an X server, which greetd does not start. tuigreet
          # wraps them in `startx` (its --xsession-wrapper default), which is why
          # displayManager.startx is enabled below.
          "--xsessions ${sessions}/xsessions"
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
    gnome.gnome-keyring.enable = true;

    xserver = {
      enable = true;
      # Provides `startx` and /etc/X11/xinit/xserverrc (which carries
      # displayManager.xserverArgs). tuigreet's --xsession-wrapper defaults to
      # `startx`, so this is what makes the awesome session launchable under
      # greetd, which manages no X server of its own. Enabling it also turns off
      # the lightdm auto-enable default in xserver.nix -- as does greetd.
      displayManager.startx.enable = true;
      # Only "nvidia" belongs here. The PRIME module in ./nvidia-prime.nix adds
      # its own "modesetting" entry carrying `BusID "PCI:0:2:0"`; listing
      # "modesetting" here as well emits a second, BusID-less
      # Device-modesetting[0]/Screen-modesetting[0] pair into xorg.conf.
      videoDrivers = [
        "nvidia"
      ];
      xkb.layout = "us,se";
      xkb.variant = "euro,";
      xkb.options = "grp:ctrls_toggle";
      autoRepeatDelay = 500;
      autoRepeatInterval = 70;

      windowManager.awesome = {
        enable = true;
        luaModules = with pkgs; [
          luaPackages.luarocks
          luaPackages.luadbi
          #luaPackages.connman_dbus
          extraLuaPackages.connman_widget
          extraLuaPackages.dbus_proxy
          extraLuaPackages.enum
          extraLuaPackages.media_player
          extraLuaPackages.power_widget
          extraLuaPackages.pulseaudio_dbus
          extraLuaPackages.pulseaudio_widget
          extraLuaPackages.upower_dbus
        ];
      };

      xrandrHeads = [
        {
          output = "DP-2-1";
        }
        {
          output = "DP-2-2";
          primary = true;
        }
        {
          output = "eDP-1";
        }
      ];

    };

  };

  xdg.portal.enable = true;
  xdg.portal.wlr.enable = true; # important
  xdg.portal.extraPortals = with pkgs; [
    xdg-desktop-portal-gtk
    xdg-desktop-portal-wlr
  ];

  location = {
    provider = "manual";
    latitude = 51.4866;
    longitude = 3.9621;
  };

  services.redshift = {
    enable = true;
    brightness = {
      day = "1";
      night = "1";
    };
    temperature = {
      day = 5500;
      night = 3700;
    };
  };

  services.libinput.touchpad.naturalScrolling = true;

  # awesome's power_widget (rc.lua) requires upower_dbus, which proxies
  # org.freedesktop.UPower on the system bus at require() time. Without the
  # daemon the require throws `code: SERVICE_UNKNOWN`, which aborts rc.lua and
  # drops awesome to its fallback config.
  services.upower.enable = true;

  # Enable CUPS to print documents.
  services.printing.enable = true;
  services.printing.stateless = true;
  services.printing.drivers = [ pkgs.brlaser ];
  services.avahi = {
    enable = true;
    nssmdns4 = true;
    openFirewall = true;
  };

  # udev rules
  services.udev.packages = [
    pkgs.stlink
    pkgs.my-saleae-logic-2
  ];
  services.udev.extraRules = import ./config-files/ti/71-ti-permissions.rules;

  # Enable sound with pipewire.
  security.rtkit.enable = true;
  security.polkit.enable = true;
  services.pulseaudio.enable = false;
  services.pipewire = {
    enable = true;
    alsa.enable = true;
    alsa.support32Bit = true;
    pulse.enable = true;
    # If you want to use JACK applications, uncomment this
    #jack.enable = true;

    # use the example session manager (no others are packaged yet so this is enabled by default,
    # no need to redefine it in your config for now)
    #media-session.enable = true;
  };

  services.orca.enable = false;
  services.speechd.enable = false;

  virtualisation.docker.enable = true;
  virtualisation.docker.storageDriver = "btrfs";

  nix.settings.trusted-users = [
    "root"
    "@wheel"
  ];

  # Allow unfree packages
  nixpkgs.config.allowUnfree = true;
  nixpkgs.config.permittedInsecurePackages = [
    "xpdf-4.06"
  ];

  environment.variables = {
    EDITOR = "vim";
  };

  environment.pathsToLink = [ "/libexec" ]; # links /libexec from derivations to /run/current-system/sw

  # List packages installed in system profile. To search, run:
  # $ nix search wget
  environment.systemPackages = with pkgs; [
    android-tools
    autorandr
    brightnessctl
    btrbk
    direnv
    dunst
    git
    grim
    hyprland
    kitty
    mc
    networkmanagerapplet
    nixfmt
    pipewire
    playerctl
    redshift
    my-saleae-logic-2
    screen
    slurp
    unzip
    walker
    wget
    wireplumber
    wl-clipboard
    wofi
    zip
  ];

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
  # involvement. services.greetd above filters it out of the list tuigreet
  # offers, precisely so it cannot be chosen by accident.
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
  # filtering in services.greetd above.
  services.elephant.enable = true;

  programs.dconf.enable = true;
  programs.nix-ld.enable = true;
  programs.nix-ld.libraries = [ ];
  programs.thunar.enable = true;

  fonts.packages = with pkgs; [
    dina-font
    fira-code
    fira-code-symbols
    font-awesome
    liberation_ttf
    mplus-outline-fonts.githubRelease
    noto-fonts
    noto-fonts-cjk-sans
    noto-fonts-color-emoji
    proggyfonts
  ];

  # Some programs need SUID wrappers, can be configured further or are
  # started in user sessions.
  # programs.mtr.enable = true;
  # programs.gnupg.agent = {
  #   enable = true;
  #   enableSSHSupport = true;
  # };

  # List services that you want to enable:

  # Enable the OpenSSH daemon.
  # services.openssh.enable = true;
  # services.openssh.settings.PermitRootLogin = "no";
  # services.openssh.settings.PasswordAuthentication = false;

  # Open ports in the firewall.
  # networking.firewall.allowedTCPPorts = [ ... ];
  # networking.firewall.allowedUDPPorts = [ ... ];
  # Or disable the firewall altogether.
  # networking.firewall.enable = false;

  # This value determines the NixOS release from which the default
  # settings for stateful data, like file locations and database versions
  # on your system were taken. It‘s perfectly fine and recommended to leave
  # this value at the release version of the first install of this system.
  # Before changing this value read the documentation for this option
  # (e.g. man configuration.nix or on https://nixos.org/nixos/options.html).
  system.stateVersion = "22.11"; # Did you read the comment?

}
