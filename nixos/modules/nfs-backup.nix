# NFS backup and restore module
#
# Provides automatic backup of stack config directories to NFS,
# and restore on boot. This preserves application state across
# VM rebuilds.
{ config, pkgs, lib, nfsConfig, ... }:

with lib;

let
  cfg = config.nfsBackup;
in
{
  options.nfsBackup = {
    enable = mkEnableOption "NFS backup for stack configs";

    stackName = mkOption {
      type = types.str;
      description = "Stack name for backup path";
    };
  };

  config = mkIf cfg.enable {
    # ============================================================
    # Backup Script
    # ============================================================
    environment.etc."stacks/backup-to-nfs.sh" = {
      mode = "0755";
      text = ''
        #!${pkgs.bash}/bin/bash
        set -euo pipefail
        export PATH="${pkgs.coreutils}/bin:${pkgs.util-linux}/bin:${pkgs.nfs-utils}/bin:${pkgs.rsync}/bin:$PATH"

        STACK="${cfg.stackName}"
        NFS_SERVER="${nfsConfig.server}"
        NFS_EXPORT="${nfsConfig.export}"
        BACKUP_SUBDIR="${nfsConfig.backupSubdir}/$STACK"
        LOCAL_PATH="/opt/stacks/$STACK"
        MOUNT_POINT="/mnt/nfs-backup"

        echo "[$(date)] Starting backup for $STACK..."

        # Mount NFS
        mkdir -p "$MOUNT_POINT"
        if ! mountpoint -q "$MOUNT_POINT"; then
          mount -t nfs "$NFS_SERVER:$NFS_EXPORT" "$MOUNT_POINT" || {
            echo "ERROR: Failed to mount NFS"
            exit 1
          }
        fi
        trap "umount '$MOUNT_POINT' 2>/dev/null || true" EXIT

        # Ensure backup directory exists
        mkdir -p "$MOUNT_POINT/$BACKUP_SUBDIR"

        # Sync config directory
        if [ -d "$LOCAL_PATH/config" ]; then
          rsync -a --delete --no-owner --no-group \
            "$LOCAL_PATH/config/" \
            "$MOUNT_POINT/$BACKUP_SUBDIR/config/"
          echo "[$(date)] Backup completed successfully"
        else
          echo "[$(date)] No config directory found at $LOCAL_PATH/config, skipping"
        fi
      '';
    };

    # ============================================================
    # Restore Script
    # ============================================================
    environment.etc."stacks/restore-nfs-backup.sh" = {
      mode = "0755";
      text = ''
        #!${pkgs.bash}/bin/bash
        set -euo pipefail
        export PATH="${pkgs.coreutils}/bin:${pkgs.util-linux}/bin:${pkgs.nfs-utils}/bin:$PATH"

        STACK="${cfg.stackName}"
        NFS_SERVER="${nfsConfig.server}"
        NFS_EXPORT="${nfsConfig.export}"
        BACKUP_SUBDIR="${nfsConfig.backupSubdir}/$STACK"
        LOCAL_PATH="/opt/stacks/$STACK"
        MOUNT_POINT="/mnt/nfs-backup"

        echo "[$(date)] Checking for backup to restore for $STACK..."

        # Mount NFS
        mkdir -p "$MOUNT_POINT"
        if ! mountpoint -q "$MOUNT_POINT"; then
          mount -t nfs "$NFS_SERVER:$NFS_EXPORT" "$MOUNT_POINT" || {
            echo "WARNING: Failed to mount NFS, skipping restore"
            exit 0
          }
        fi
        trap "umount '$MOUNT_POINT' 2>/dev/null || true" EXIT

        # Restore config if backup exists and local config doesn't
        if [ -d "$MOUNT_POINT/$BACKUP_SUBDIR/config" ]; then
          if [ ! -d "$LOCAL_PATH/config" ] || [ -z "$(ls -A "$LOCAL_PATH/config" 2>/dev/null)" ]; then
            mkdir -p "$LOCAL_PATH"
            cp -r "$MOUNT_POINT/$BACKUP_SUBDIR/config" "$LOCAL_PATH/"
            echo "[$(date)] Restored config from NFS backup"
          else
            echo "[$(date)] Local config already exists, skipping restore"
          fi
        else
          echo "[$(date)] No backup found at $MOUNT_POINT/$BACKUP_SUBDIR/config, starting fresh"
        fi
      '';
    };

    # ============================================================
    # Backup Timer (Hourly)
    # ============================================================
    systemd.services.stack-backup = {
      description = "Backup stack config to NFS";
      serviceConfig = {
        Type = "oneshot";
        ExecStart = "/etc/stacks/backup-to-nfs.sh";
      };
    };

    systemd.timers.stack-backup = {
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnCalendar = "hourly";
        Persistent = true;
        RandomizedDelaySec = "5m";
      };
    };

    # ============================================================
    # Restore Service (runs once on boot)
    # ============================================================
    systemd.services.stack-restore = {
      description = "Restore stack config from NFS on boot";
      wantedBy = [ "multi-user.target" ];
      after = [ "network-online.target" ];
      wants = [ "network-online.target" ];

      serviceConfig = {
        Type = "oneshot";
        ExecStart = "/etc/stacks/restore-nfs-backup.sh";
        RemainAfterExit = true;
      };
    };
  };
}
