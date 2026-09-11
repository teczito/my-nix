# PLACEHOLDER -- the machine does not exist yet.
#
# Replace this file wholesale with the one `nixos-generate-config` writes on the
# real hardware; do not hand-merge it. It exists only so that
# `nixosConfigurations.server` evaluates and builds from the laptop before there
# is anything to install it on, which is what makes the rest of this host's
# config reviewable in advance.
#
# The root filesystem below is a fiction that satisfies the "you must specify a
# root file system" assertion. Nothing here has been checked against real disks.
{ lib, modulesPath, ... }:

{
  imports = [ (modulesPath + "/installer/scan/not-detected.nix") ];

  boot.initrd.availableKernelModules = [
    "ahci"
    "nvme"
    "sd_mod"
    "usb_storage"
    "usbhid"
    "xhci_pci"
  ];
  boot.initrd.kernelModules = [ ];
  # KVM module for the VM-host role. "kvm-amd" if the CPU turns out to be AMD;
  # the generated file will get this right.
  boot.kernelModules = [ "kvm-intel" ];
  boot.extraModulePackages = [ ];

  fileSystems."/" = {
    device = "/dev/disk/by-label/nixos";
    fsType = "ext4";
  };

  fileSystems."/boot" = {
    device = "/dev/disk/by-label/ESP";
    fsType = "vfat";
    options = [
      "fmask=0077"
      "dmask=0077"
    ];
  };

  swapDevices = [ ];

  networking.useDHCP = lib.mkDefault true;
}
