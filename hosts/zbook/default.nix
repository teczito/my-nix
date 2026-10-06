# HP ZBook Fury 15.6" G8 -- Xeon W-11955M, Intel iGPU + NVIDIA RTX A2000 on
# PRIME offload. Everything here is true of this machine and no other; anything
# shared lives in ../../modules and is imported below.
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

    ../../modules/common
    ../../modules/desktop
    ../../users/ruben/desktop.nix

    ../../modules/hardware/nvidia-prime.nix

    ./backup-jobs.nix
    ../../modules/services/backup.nix
    ../../modules/services/devices.nix
    ../../modules/services/docker.nix
    ../../modules/services/printing.nix
  ];

  # Bootloader. Per-machine by nature: this is the EFI partition and the
  # firmware of this laptop.
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

  # networking.hostName comes from the host directory name, set by mkHost in
  # flake.nix, so hosts/<name> and the machine name cannot drift apart.
  # networking.wireless.enable = true;  # Enables wireless support via wpa_supplicant.

  # ssh-server on demand. The unit itself comes from modules/common/ssh.nix;
  # this is the half that keeps it out of multi-user.target, so nothing listens
  # on 22 until `sudo systemctl start sshd`. Deliberate on a laptop -- and the
  # opposite of what a headless host wants.
  systemd.services.sshd.wantedBy = lib.mkForce [ ];

  # Laptop hardware: there is a touchpad to configure.
  services.libinput.touchpad.naturalScrolling = true;

  # /var/lib/docker is on the btrfs root here. See modules/services/docker.nix.
  virtualisation.docker.storageDriver = "btrfs";

  # Some programs need SUID wrappers, can be configured further or are
  # started in user sessions.
  # programs.mtr.enable = true;
  # programs.gnupg.agent = {
  #   enable = true;
  #   enableSSHSupport = true;
  # };

  # This value determines the NixOS release from which the default
  # settings for stateful data, like file locations and database versions
  # on your system were taken. It's perfectly fine and recommended to leave
  # this value at the release version of the first install of this system.
  # Before changing this value read the documentation for this option
  # (e.g. man configuration.nix or on https://nixos.org/nixos/options.html).
  system.stateVersion = "22.11"; # Did you read the comment?

  # Same idea, one level down: home-manager keeps its own compatibility marker
  # and it is equally per-machine.
  home-manager.users.ruben.home.stateVersion = "23.05";
}
