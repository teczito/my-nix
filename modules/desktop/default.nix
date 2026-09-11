{ ... }:

{
  imports = [
    ./apps.nix
    ./audio.nix
    ./fonts.nix
    ./greetd.nix
    ./hyprland.nix
    ./portals.nix
  ];

  # Accessibility daemons, off deliberately.
  services.orca.enable = false;
  services.speechd.enable = false;
}
