#!/bin/bash
set -euo pipefail

STACK="${stack}"
NFS_SERVER="${nfs_server}"
NFS_EXPORT="${nfs_export}"
BACKUP_SUBDIR="${nfs_docker_data}/backups/$STACK"
LOCAL_PATH="/opt/stacks/$STACK"
MOUNT_POINT="/mnt/nfs-backup"

mkdir -p "$MOUNT_POINT"

if mount -t nfs -o nfsvers=4,soft,timeo=10 "$NFS_SERVER:$NFS_EXPORT" "$MOUNT_POINT" 2>/dev/null; then
  echo "NFS mounted, checking for backup..."
  if [ -d "$MOUNT_POINT/$BACKUP_SUBDIR/config" ]; then
    echo "Backup found, restoring config..."
    cp -a "$MOUNT_POINT/$BACKUP_SUBDIR/config" "$LOCAL_PATH/"
    echo "Restored config from backup"
  else
    echo "No backup found at $BACKUP_SUBDIR/config"
  fi
  umount "$MOUNT_POINT"
else
  echo "No NFS backup found - starting with fresh config"
fi

rmdir "$MOUNT_POINT" 2>/dev/null || true
