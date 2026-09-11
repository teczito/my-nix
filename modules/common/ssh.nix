{ ... }:

{
  # The unit exists on every host; whether it is *started* at boot is a per-host
  # decision. hosts/zbook/default.nix forces it off and starts it on demand.
  services.openssh.enable = true;
  # services.openssh.settings.PermitRootLogin = "no";
  # services.openssh.settings.PasswordAuthentication = false;
}
