{ pkgs, ... }:

{
  virtualisation.libvirtd = {
    enable = true;
    qemu = {
      package = pkgs.qemu_kvm;
      # Guests run as the qemu user, not root.
      runAsRoot = false;
      # UEFI firmware for guests no longer needs configuring: the
      # virtualisation.libvirtd.qemu.ovmf submodule was removed and every OVMF
      # image QEMU ships is available by default.
      #
      # Emulated TPM 2.0, which Windows 11 guests require.
      swtpm.enable = true;
    };
  };

  # Lets guests be reached on the LAN rather than only through libvirt's NAT.
  # Needs the real interface name, so it waits for the hardware.
  # virtualisation.libvirtd.allowedBridges = [ "br0" ];
  # networking.bridges.br0.interfaces = [ "enpXsY" ];

  # No virt-manager here: the GUI belongs on the workstation, which connects
  # over qemu+ssh://<user>@<host>/system. virsh comes with libvirtd.
}
