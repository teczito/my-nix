{ ... }:

# For a host whose job includes compiling things.
{
  nix.settings = {
    # Keep build-time dependencies and .drv files around so a rebuilt dev shell
    # or a `nix develop` does not re-fetch what it just had. Costs store space,
    # which nix.gc below bounds.
    keep-outputs = true;
    keep-derivations = true;
  };

  nix.gc = {
    automatic = true;
    dates = "weekly";
    options = "--delete-older-than 30d";
  };

  # Hardlink identical files in the store. Worth it on a machine that builds a
  # lot of near-identical closures.
  nix.optimise.automatic = true;

  boot.tmp.cleanOnBoot = true;

  # To let the workstation offload builds here, add on the *client*:
  #
  #   nix.distributedBuilds = true;
  #   nix.buildMachines = [{
  #     hostName = "<host>"; system = "x86_64-linux"; protocol = "ssh-ng";
  #     maxJobs = 8; supportedFeatures = [ "nixos-test" "benchmark" "big-parallel" "kvm" ];
  #   }];
  #
  # and make sure the client's root ssh key is authorised for a trusted user here.
}
