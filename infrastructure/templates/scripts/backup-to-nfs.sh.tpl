#!/bin/bash
set -euo pipefail

STACK="${stack}"
NFS_SERVER="${nfs_server}"
NFS_EXPORT="${nfs_export}"
BACKUP_SUBDIR="${nfs_docker_data}/backups/$STACK"
LOCAL_PATH="/opt/stacks/$STACK"
MOUNT_POINT="/mnt/nfs-backup-$$"

mkdir -p "$MOUNT_POINT"

if mount -t nfs -o nfsvers=4,soft,timeo=30 "$NFS_SERVER:$NFS_EXPORT" "$MOUNT_POINT" 2>/dev/null; then
  # Create backup directory if it doesn't exist
  mkdir -p "$MOUNT_POINT/$BACKUP_SUBDIR"
  # Sync config directory only (secrets managed by 1Password)
  # Use --no-owner --no-group because NFS root_squash prevents chown
  rsync -a --delete --no-owner --no-group "$LOCAL_PATH/config/" "$MOUNT_POINT/$BACKUP_SUBDIR/config/"
  umount "$MOUNT_POINT"
  rmdir "$MOUNT_POINT"
  logger -t backup-nfs "Backup of $STACK config completed successfully"
else
  rmdir "$MOUNT_POINT" 2>/dev/null || true
  logger -t backup-nfs "Backup of $STACK failed - NFS unavailable"
fi
