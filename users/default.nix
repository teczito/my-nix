{ ... }:

{
  imports = [
    # The CLI base. users/ruben/desktop.nix is the graphical layer on top, and
    # is imported by the hosts that want it.
    ./ruben
  ];
}
