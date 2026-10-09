# This file defines overlays
{ inputs, ... }:
let
  # This one brings our custom packages from the 'pkgs' directory
  additions = final: _prev: import ../pkgs final.pkgs;

  # This one contains whatever you want to overlay
  # You can change versions, add patches, set compilation flags, anything really.
  # https://nixos.wiki/wiki/Overlays
  modifications = final: prev: {
    # lan-mouse's wlroots backend types through zwp_virtual_keyboard_v1, which
    # niri (smithay) forwards straight to the focused client: niri's own
    # keybindings never see those keys, and lan-mouse's hand-rolled modifier
    # table reports AltGr as Alt. The patch sends keys through a /dev/uinput
    # keyboard instead, which niri treats like real hardware. Needs uinput
    # access (hosts/zbook); without it lan-mouse falls back to the old path.
    lan-mouse = prev.lan-mouse.overrideAttrs (old: {
      patches = (old.patches or [ ]) ++ [ ./patches/lan-mouse-uinput-keyboard.patch ];
    });
  };

  # When applied, the unstable nixpkgs set (declared in the flake inputs) will
  # be accessible through 'pkgs.unstable'
  #unstable-packages = final: _prev: {
  #  unstable = import inputs.nixpkgs-unstable {
  #    system = final.system;
  #    config.allowUnfree = true;
  #  };
  #};
in
[
  additions
  modifications
]
