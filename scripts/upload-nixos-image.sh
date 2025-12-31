#!/usr/bin/env bash
# Upload NixOS VMA image to Proxmox shared storage and create templates
#
# Usage: ./scripts/upload-nixos-image.sh
#
# This script:
# 1. Builds the NixOS Proxmox image (if not already built)
# 2. Uploads the VMA to Proxmox
# 3. Extracts and imports disk to NFS shared storage
# 4. Creates template VMs on each node (sharing the same disk)
#
# Environment variables (from .env via direnv):
#   TF_VAR_proxmox_api_url - Proxmox API URL (used to derive host)
#   PROXMOX_HOST - Override Proxmox host (optional)
#   PROXMOX_USER - SSH user for Proxmox (default: root)
#   PROXMOX_STORAGE - Storage for template disk (default: nfs-infrastructure)

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# Configuration
if [ -n "${TF_VAR_proxmox_api_url:-}" ]; then
  PROXMOX_HOST="${PROXMOX_HOST:-$(echo "$TF_VAR_proxmox_api_url" | sed -E 's|https?://([^:/]+).*|\1|')}"
else
  PROXMOX_HOST="${PROXMOX_HOST:-}"
fi

PROXMOX_USER="${PROXMOX_USER:-root}"
PROXMOX_STORAGE="${PROXMOX_STORAGE:-nfs-infrastructure}"
TEMPLATE_NAME="${TEMPLATE_NAME:-nixos-template}"

# Template VMIDs per node (must match main.tf)
declare -A NODE_TEMPLATES=(
  ["strongmad"]=9000
  ["strongbad"]=9001
)
PRIMARY_NODE="strongmad"
PRIMARY_VMID="${NODE_TEMPLATES[$PRIMARY_NODE]}"

# Paths
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
NIXOS_DIR="$PROJECT_ROOT/nixos"
IMAGE_PATH="$NIXOS_DIR/result"

# Validate required config
if [ -z "$PROXMOX_HOST" ]; then
  log_error "PROXMOX_HOST not set. Set TF_VAR_proxmox_api_url or PROXMOX_HOST environment variable."
  exit 1
fi

echo "=== NixOS Image Upload Script (Shared Storage) ==="
echo ""
log_info "Primary Proxmox Host: $PROXMOX_HOST"
log_info "Storage: $PROXMOX_STORAGE"
log_info "Primary Template: $PRIMARY_NODE (VMID $PRIMARY_VMID)"
for node in "${!NODE_TEMPLATES[@]}"; do
  if [ "$node" != "$PRIMARY_NODE" ]; then
    log_info "Secondary Template: $node (VMID ${NODE_TEMPLATES[$node]})"
  fi
done
echo ""

# Step 1: Build the image if needed
if [ ! -L "$IMAGE_PATH" ] || [ ! -e "$IMAGE_PATH" ]; then
  log_info "Building NixOS Proxmox image..."
  cd "$NIXOS_DIR"
  nix build .#proxmox-image
  cd "$PROJECT_ROOT"
else
  log_info "Using existing image at $IMAGE_PATH"
fi

# Find the VMA file
VMA_FILE=$(find -L "$IMAGE_PATH" -name "*.vma.zst" -o -name "*.vma" 2>/dev/null | head -1)
if [ -z "$VMA_FILE" ]; then
  log_error "No VMA file found in $IMAGE_PATH"
  log_error "Try running: cd nixos && nix build .#proxmox-image"
  exit 1
fi

log_info "Found image: $VMA_FILE"

# Step 2: Decompress if needed
TEMP_VMA=""
if [[ "$VMA_FILE" == *.zst ]]; then
  log_info "Decompressing image..."
  TEMP_VMA="/tmp/nixos-$(date +%s).vma"
  zstd -d "$VMA_FILE" -o "$TEMP_VMA"
  VMA_FILE="$TEMP_VMA"
  trap "rm -f '$TEMP_VMA'" EXIT
fi

# Step 3: Upload to primary Proxmox node
log_info "Uploading to Proxmox host $PROXMOX_HOST..."
scp -o StrictHostKeyChecking=accept-new "$VMA_FILE" "${PROXMOX_USER}@${PROXMOX_HOST}:/tmp/nixos.vma"

# Step 4: Extract VMA and import disk to shared storage
log_info "Extracting VMA and importing disk to $PROXMOX_STORAGE..."

ssh -o StrictHostKeyChecking=accept-new "${PROXMOX_USER}@${PROXMOX_HOST}" bash <<EOF
set -e

# Remove existing primary template if present
if qm status $PRIMARY_VMID &>/dev/null; then
  echo "Removing existing template $PRIMARY_VMID..."
  qm destroy $PRIMARY_VMID --purge || true
fi

# Extract VMA to get raw disk
echo "Extracting VMA..."
rm -rf /tmp/nixos-extract
vma extract /tmp/nixos.vma /tmp/nixos-extract/

# Find the disk image
DISK_IMAGE=\$(ls /tmp/nixos-extract/*.raw 2>/dev/null | head -1)
if [ -z "\$DISK_IMAGE" ]; then
  echo "ERROR: No raw disk found in VMA"
  exit 1
fi

# Create VM and import disk
echo "Creating VM $PRIMARY_VMID and importing disk..."
qm create $PRIMARY_VMID --name "$TEMPLATE_NAME" --ostype l26 --scsihw virtio-scsi-single
qm importdisk $PRIMARY_VMID "\$DISK_IMAGE" $PROXMOX_STORAGE

# Attach and configure
qm set $PRIMARY_VMID --virtio0 $PROXMOX_STORAGE:$PRIMARY_VMID/vm-$PRIMARY_VMID-disk-0.raw
qm set $PRIMARY_VMID --boot c --bootdisk virtio0
qm set $PRIMARY_VMID --agent enabled=1
qm set $PRIMARY_VMID --serial0 socket
qm set $PRIMARY_VMID --vga std
qm set $PRIMARY_VMID --description "NixOS base image for Colmena-managed VMs (shared storage). Built: \$(date -Iseconds)"
qm set $PRIMARY_VMID --tags "template,nixos,tofu"

# Convert to template
echo "Converting to template..."
qm template $PRIMARY_VMID

# Cleanup
rm -rf /tmp/nixos-extract /tmp/nixos.vma

echo "Primary template $PRIMARY_VMID created successfully!"
EOF

# Step 5: Create secondary templates on other nodes
for node in "${!NODE_TEMPLATES[@]}"; do
  if [ "$node" != "$PRIMARY_NODE" ]; then
    vmid="${NODE_TEMPLATES[$node]}"
    log_info "Creating secondary template on $node (VMID $vmid)..."

    ssh -o StrictHostKeyChecking=accept-new "${PROXMOX_USER}@${node}" bash <<EOF
set -e

# Remove existing template if present
if qm status $vmid &>/dev/null; then
  echo "Removing existing template $vmid..."
  qm destroy $vmid --purge || true
fi

# Create template pointing to shared disk
qm create $vmid \
  --name "$TEMPLATE_NAME" \
  --ostype l26 \
  --scsihw virtio-scsi-single \
  --virtio0 $PROXMOX_STORAGE:$PRIMARY_VMID/base-$PRIMARY_VMID-disk-0.raw \
  --boot c \
  --bootdisk virtio0 \
  --agent enabled=1 \
  --serial0 socket \
  --vga std \
  --description "NixOS base image (shares disk with template $PRIMARY_VMID on $PRIMARY_NODE)" \
  --tags "template,nixos,tofu"

qm template $vmid
echo "Secondary template $vmid created on $node!"
EOF
  fi
done

echo ""
echo "=== Upload Complete ==="
echo ""
log_info "Templates created on shared storage ($PROXMOX_STORAGE):"
for node in "${!NODE_TEMPLATES[@]}"; do
  log_info "  - $node: VMID ${NODE_TEMPLATES[$node]}"
done
echo ""
log_info "All templates share the same disk image."
log_info "You can now use these templates in OpenTofu."
