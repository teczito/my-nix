{ ... }:

{
  imports = [
    ./locale.nix
    ./networking.nix
    ./nix.nix
    ./packages.nix
    ./ssh.nix
  ];

  # Wanted well beyond the desktop -- logind actions, and the polkit rules that
  # daemons like libvirt ship. Its old neighbour `security.rtkit` is
  # audio-specific and stayed with pipewire in modules/desktop/audio.nix.
  security.polkit.enable = true;

  # Lets unpatched, non-Nix binaries (downloaded toolchains, vendor SDKs) find an
  # interpreter and libraries. Useful anywhere software gets built or run.
  programs.nix-ld.enable = true;
  programs.nix-ld.libraries = [ ];

  services.udisks2.enable = true;
}
