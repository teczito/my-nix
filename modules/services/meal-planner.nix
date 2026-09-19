# The family meal planner: one FastAPI process and a SQLite file, read from
# five phones on the LAN.
#
# The module itself ships with the app, so the only things decided here are
# whether this machine runs it and who may reach it. Everything else -- the
# state directory, the daily check at seven, the nightly backup -- is the
# module's own default, and the reasons for those defaults live in its source
# rather than being restated here.
{ inputs, ... }:

{
  imports = [ inputs.meal-planner.nixosModules.default ];

  services.meal-planner = {
    enable = true;
    # The firewall is on and the whole point is that five people reach this
    # from their phones. The module leaves the port shut by default because
    # opening one is a decision about the network; this is that decision.
    openFirewall = true;
  };
}
