{
  config,
  lib,
  pkgs,
  ...
}:

# btrbk jobs, declared once each.
#
# This used to be two files that had to be edited together: one wrote the
# config into /etc/btrbk/, the other defined a systemd timer and service naming
# that exact path, and renaming the config silently broke the unit. Here one
# job name generates all three, so they cannot drift.
let
  cfg = config.local.btrbk;
in
{
  options.local.btrbk.jobs = lib.mkOption {
    default = { };
    description = ''
      btrbk jobs. Each entry generates /etc/btrbk/btrbk-<name>.conf, a oneshot
      <name>.service that runs btrbk against it, and a <name>.timer.
    '';
    example = lib.literalExpression ''
      {
        snapshots-home = {
          onBootSec = "5m";
          onUnitActiveSec = "1h";
          settings = "subvolume /mnt/btr_pool/nixos-home";
        };
      }
    '';
    type = lib.types.attrsOf (
      lib.types.submodule {
        options = {
          settings = lib.mkOption {
            type = lib.types.lines;
            description = "Body of the generated btrbk config file.";
          };
          onBootSec = lib.mkOption {
            type = lib.types.str;
            default = "5m";
            description = "Timer delay after boot.";
          };
          onUnitActiveSec = lib.mkOption {
            type = lib.types.nullOr lib.types.str;
            default = null;
            description = "Repeat interval. Null runs the job once per boot.";
          };
        };
      }
    );
  };

  config = lib.mkIf (cfg.jobs != { }) {
    environment.systemPackages = [ pkgs.btrbk ];

    environment.etc = lib.mapAttrs' (
      name: job:
      lib.nameValuePair "btrbk/btrbk-${name}.conf" {
        text = job.settings;
        # The UNIX file mode bits
        mode = "0550";
      }
    ) cfg.jobs;

    systemd.timers = lib.mapAttrs (name: job: {
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnBootSec = job.onBootSec;
        Unit = "${name}.service";
      }
      // lib.optionalAttrs (job.onUnitActiveSec != null) {
        OnUnitActiveSec = job.onUnitActiveSec;
      };
    }) cfg.jobs;

    systemd.services = lib.mapAttrs (name: _job: {
      script = ''
        set -eu
        ${pkgs.btrbk}/bin/btrbk -c /etc/btrbk/btrbk-${name}.conf -v run
      '';
      serviceConfig = {
        Type = "oneshot";
        User = "root";
      };
    }) cfg.jobs;
  };
}
