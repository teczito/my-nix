{ pkgs, ... }:

{
  systemd.timers."backup-to-ssd" = {
    wantedBy = [ "timers.target" ];
      timerConfig = {
        OnBootSec = "20m";
        OnUnitActiveSec = "1h";
        Unit = "backup-to-ssd.service";
      };
  };

  systemd.services."backup-to-ssd" = {
    script = ''
      set -eu
      ${pkgs.btrbk}/bin/btrbk -c /etc/btrbk/btrbk-backup-to-ssd.conf -v run
    '';
    serviceConfig = {
      Type = "oneshot";
      User = "root";
    };
  };

  systemd.timers."snapshots-home" = {
    wantedBy = [ "timers.target" ];
      timerConfig = {
        OnBootSec = "5m";
        OnUnitActiveSec = "1h";
        Unit = "snapshots-home.service";
      };
  };

  systemd.services."snapshots-home" = {
    script = ''
      set -eu
      ${pkgs.btrbk}/bin/btrbk -c /etc/btrbk/btrbk-snapshots-home.conf -v run
    '';
    serviceConfig = {
      Type = "oneshot";
      User = "root";
    };
  };

  systemd.timers."snapshots-root" = {
    wantedBy = [ "timers.target" ];
      timerConfig = {
        OnBootSec = "10m";
        Unit = "snapshots-root.service";
      };
  };

  systemd.services."snapshots-root" = {
    script = ''
      set -eu
      ${pkgs.btrbk}/bin/btrbk -c /etc/btrbk/btrbk-snapshots-root.conf -v run
    '';
    serviceConfig = {
      Type = "oneshot";
      User = "root";
    };
  };
}
