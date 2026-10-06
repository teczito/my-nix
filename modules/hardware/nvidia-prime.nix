{
  config,
  pkgs,
  lib,
  ...
}:

# Discrete NVIDIA RTX A2000 Mobile (GA107GLM, Ampere) on PCI:1:0:0, run as a
# PRIME render-offload sink behind the Tiger Lake-H iGPU on PCI:0:2:0.
#
# The iGPU keeps every display and does all the compositing; the NVIDIA card
# stays parked at D3cold until something is launched through `nvidia-offload`,
# at which point it wakes, renders, and hands the result back to the iGPU.
# This replaces the old `hardware.nvidiaOptimus.disable` + bbswitch setup.
{
  # services.xserver.enable is here, not with any desktop module, because it is
  # not about running an X session -- there is none. The NVIDIA module gates
  #   boot.kernelModules = [ "nvidia" "nvidia_modeset" "nvidia_drm" ]
  # on it (nixos/modules/hardware/video/nvidia.nix), so with it off the
  # driver's kernel modules never load at boot and PRIME offload breaks.
  services.xserver.enable = true;

  # Only "nvidia" belongs here. The PRIME module below adds its own
  # "modesetting" entry carrying `BusID "PCI:0:2:0"`; listing "modesetting"
  # here as well emits a second, BusID-less
  # Device-modesetting[0]/Screen-modesetting[0] pair into xorg.conf.
  # Note this list is read independently of services.xserver.enable
  # (`lib.elem "nvidia" config.services.xserver.videoDrivers`), so it is the
  # list, not the flag, that turns the driver on.
  services.xserver.videoDrivers = [ "nvidia" ];

  hardware.graphics.enable = true;

  # VAAPI for the iGPU, which still drives all output. (The old
  # `libva-vdpau-driver` here was dead weight: it implements VA-API on top of
  # VDPAU, and nothing on this machine provides VDPAU.)
  hardware.graphics.extraPackages = with pkgs; [
    intel-media-driver
  ];

  hardware.nvidia = {
    package = config.boot.kernelPackages.nvidiaPackages.production;

    # Ampere is fully supported by the open kernel modules. This must be set
    # explicitly: the option defaults to `null` on driver >= 560, and `null`
    # trips an assertion in the nvidia module.
    open = true;

    modesetting.enable = true;
    nvidiaSettings = true;

    powerManagement.enable = true;
    # Runtime D3: the card powers itself down when no client holds it open.
    # Close to, but not quite, the ACPI cut bbswitch used to do -- expect
    # roughly 1-2 W more at idle.
    powerManagement.finegrained = true;

    prime = {
      offload.enable = true;
      offload.enableOffloadCmd = true; # provides the `nvidia-offload` wrapper
      intelBusId = "PCI:0:2:0";
      nvidiaBusId = "PCI:1:0:0";
    };
  };

  # Stable aliases for the two DRM nodes, consumed by the `debug` block in
  # config-files/niri/config.kdl: niri renders on /dev/dri/igpu (the iGPU that
  # owns every display) and ignores /dev/dri/dgpu, so it never opens the NVIDIA
  # card and leaves it in D3cold until `nvidia-offload` wakes it.
  #
  # Plain /dev/dri/cardN would do, but the numbering is not stable across
  # boots -- the NVIDIA card currently takes card0 and the iGPU card1. Matching
  # on the PCI slot (0000:00:02.0 and 0000:01:00.0, the intelBusId and
  # nvidiaBusId above) keeps each name on the right card however the DRM nodes
  # happen to enumerate. The names are also deliberately colon-free: Hyprland,
  # which used to consume igpu through AQ_DRM_DEVICES, split that variable on
  # colons, which ruled out the /dev/dri/by-path/pci-0000:00:02.0-card form.
  #
  # services.udev.extraRules is a `lines` option, so this definition merges
  # with the TI rules in modules/services/devices.nix rather than colliding.
  # mkBefore, not bare assignment: `lines` options merge in module order, which
  # is not the order of a host's imports list and is not worth depending on.
  # This pins these symlinks above the TI rules in the generated file.
  services.udev.extraRules = lib.mkBefore ''
    KERNEL=="card*", SUBSYSTEM=="drm", DEVPATH=="*/0000:00:02.0/drm/card*", SYMLINK+="dri/igpu"
    KERNEL=="card*", SUBSYSTEM=="drm", DEVPATH=="*/0000:01:00.0/drm/card*", SYMLINK+="dri/dgpu"
  '';
}
