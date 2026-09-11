# The server: local LLM, VM host, containers, and compiling things. Mainly
# headless, with a monitor attached occasionally -- hence the desktop import.
#
# NOTE: the hardware does not exist yet. ./hardware-configuration.nix is a
# placeholder and everything marked "placeholder" below is a guess that the real
# machine gets to overrule.
{ ... }:

{
  imports = [
    ./hardware-configuration.nix

    ../../modules/common

    # Hyprland and the rest of the graphical stack. Nothing here needs a display
    # to boot: greetd sits on the console waiting, and a session only starts
    # when someone logs in at an attached monitor.
    #
    # users/ruben/desktop.nix is deliberately NOT imported -- that layer is
    # brave, vscode, kicad and the bench groups, which belong on the laptop.
    # Add it here if this machine ever becomes somewhere you sit.
    ../../modules/desktop

    ../../modules/services/builder.nix
    ../../modules/services/docker.nix
    ../../modules/services/llm.nix
    ../../modules/services/virtualisation.nix
  ];

  # Placeholder bootloader. The installer decides this for real.
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;
  # Headless: do not sit in a menu nobody is watching. (The zbook uses 300.)
  boot.loader.timeout = 5;

  # sshd is deliberately NOT disabled here. modules/common/ssh.nix enables the
  # unit and the stock wantedBy starts it at boot, which is the whole point of a
  # headless host -- the opposite of hosts/zbook/default.nix, which forces it
  # off. Leave password auth alone until there is a key on the machine; locking
  # it down before then locks you out.
  # services.openssh.settings.PasswordAuthentication = false;
  # services.openssh.settings.PermitRootLogin = "no";

  # virtualisation.docker.storageDriver is left unset on purpose: docker picks
  # overlay2, which is right unless /var/lib/docker turns out to be btrfs.

  # For the VM-host role. "docker" is already in the base user module.
  users.users.ruben.extraGroups = [ "libvirtd" ];

  # A fresh install, so these start at the current release rather than at the
  # laptop's 22.11. The installer's generated value should win if it differs.
  system.stateVersion = "26.11";
  home-manager.users.ruben.home.stateVersion = "26.11";
}
