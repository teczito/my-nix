{ ... }:

# What this laptop backs up. The machinery is in
# ../../modules/services/backup.nix; this is policy: which subvolumes, how
# often, and how much history to keep.
{
  local.btrbk.jobs = {
    snapshots-home = {
      onBootSec = "5m";
      onUnitActiveSec = "1h";
      settings = ''
        archive_exclude nixos-root
        archive_exclude nixos-nix

        timestamp_format        long
        snapshot_preserve_min   18h
        snapshot_preserve       48h

        snapshot_dir /mnt/btr_pool/btrbk_snapshots
        subvolume    /mnt/btr_pool/nixos-home
      '';
    };

    snapshots-root = {
      onBootSec = "10m";
      settings = ''
        archive_exclude nixos-home
        archive_exclude nixos-nix

        timestamp_format        long
        snapshot_preserve_min   18h
        snapshot_preserve       48h

        snapshot_dir /mnt/btr_pool/btrbk_snapshots
        subvolume    /mnt/btr_pool/nixos-root
      '';
    };

    backup-to-ssd = {
      onBootSec = "20m";
      onUnitActiveSec = "1h";
      settings = ''
        archive_exclude nixos-root
        archive_exclude nixos-nix

        timestamp_format        long
        snapshot_preserve_min   2d
        snapshot_preserve       14d

        target_preserve_min    no
        target_preserve        20d 10w *m

        volume /mnt/btr_pool
          target /mnt/backup_ssd
          subvolume nixos-home
      '';
    };
  };
}
