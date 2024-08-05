{ pkgs, ... }:

{
  environment.etc = {
    "btrbk/btrbk-snapshots-home.conf" = {
      text = ''
        archive_exclude nixos-root
        archive_exclude nixos-nix

        timestamp_format        long
        snapshot_preserve_min   18h
        snapshot_preserve       48h

        snapshot_dir /mnt/btr_pool/btrbk_snapshots
        subvolume    /mnt/btr_pool/nixos-home
      '';

      # The UNIX file mode bits
      mode = "0550";
    };

    "btrbk/btrbk-snapshots-root.conf" = {
      text = ''
        archive_exclude nixos-home
        archive_exclude nixos-nix

        timestamp_format        long
        snapshot_preserve_min   18h
        snapshot_preserve       48h

        snapshot_dir /mnt/btr_pool/btrbk_snapshots
        subvolume    /mnt/btr_pool/nixos-root
      '';

      # The UNIX file mode bits
      mode = "0550";
    };

    "btrbk/btrbk-backup-to-ssd.conf" = {
      text = ''
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

      # The UNIX file mode bits
      mode = "0550";
    };
  };
}
