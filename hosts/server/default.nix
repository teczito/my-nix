# The server: local LLM, VM host, containers, and compiling things. Mainly
# headless, with a monitor attached occasionally -- hence the desktop import.
# Lives at 192.168.68.105 on the LAN; ./hardware-configuration.nix is the real
# nixos-generate-config output from the install.
{ pkgs, ... }:

{
  imports = [
    ./hardware-configuration.nix

    ../../modules/common

    # Hyprland and the rest of the graphical stack. Nothing here needs a display
    # to boot: greetd sits on the console waiting, and a session only starts
    # when someone logs in at an attached monitor.
    #
    # users/ruben/desktop.nix is deliberately NOT imported -- that layer is
    # vscode, kicad and the bench groups, which belong on the laptop. Brave and
    # thunar are not in that layer: both come with ../../modules/desktop, so the
    # occasional monitor gets a browser and a file manager. Add desktop.nix here
    # if this machine ever becomes somewhere you sit.
    ../../modules/desktop

    ../../modules/services/builder.nix
    # The LAN's DNS resolver (AdGuard Home).
    ../../modules/services/dns.nix
    ../../modules/services/docker.nix
    ../../modules/services/llm.nix
    # The family meal planner. It belongs on this machine rather than the
    # laptop because it has to answer a phone at seven in the morning, and
    # because its daily check needs a route to this LAN.
    ../../modules/services/meal-planner.nix
    ../../modules/services/virtualisation.nix
  ];

  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;
  # Headless: do not sit in a menu nobody is watching. (The zbook uses 300.)
  boot.loader.timeout = 5;

  # Kernel version, as on the zbook. Worth keeping at 7.2+: nixos-generate-config
  # was run from the 7.x installer, and nixpkgs only adds the AMD 800-series USB
  # driver (xhci_pci_prom21) to the default initrd set on 7.2+. On the 6.18
  # default that module does not exist at all and the initrd build fails.
  boot.kernelPackages = pkgs.linuxPackages_latest;

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

  # Installed fresh on 26.11, so these are that release rather than the
  # laptop's 22.11. Never bump them.
  system.stateVersion = "26.11";
  home-manager.users.ruben.home.stateVersion = "26.11";
}
