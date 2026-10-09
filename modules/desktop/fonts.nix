{ pkgs, ... }:

{
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
    ubuntu-sans
    ubuntu-sans-mono
  ];

  # The Ubuntu look (users/ruben/theme.nix): Ubuntu Sans as the default UI and
  # monospace face for anything that asks fontconfig rather than naming a font.
  fonts.fontconfig.defaultFonts = {
    sansSerif = [ "Ubuntu Sans" ];
    monospace = [ "Ubuntu Sans Mono" ];
  };
}
