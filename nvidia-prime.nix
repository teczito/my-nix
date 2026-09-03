{ config, pkgs, ... }:

# Discrete NVIDIA RTX A2000 Mobile (GA107GLM, Ampere) on PCI:1:0:0, run as a
# PRIME render-offload sink behind the Tiger Lake-H iGPU on PCI:0:2:0.
#
# The iGPU keeps every display and does all the compositing; the NVIDIA card
# stays parked at D3cold until something is launched through `nvidia-offload`,
# at which point it wakes, renders, and hands the result back to the iGPU.
# This replaces the old `hardware.nvidiaOptimus.disable` + bbswitch setup.
{
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
}
