#!/usr/bin/env bash
# Upload NixOS VMA image to Proxmox and create a template
#
# Usage: ./scripts/upload-nixos-image.sh
#
# This script:
# 1. Builds the NixOS Proxmox image (if not already built)
# 2. Uploads the VMA to Proxmox
# 3. Restores it as a template VM
#
# Environment variables (from .env via direnv):
#   TF_VAR_proxmox_api_url - Proxmox API URL (used to derive host)
#   PROXMOX_HOST - Override Proxmox host (optional)
#   PROXMOX_USER - SSH user for Proxmox (default: root)
#   PROXMOX_STORAGE - Storage for template (default: local-lvm)
#   PROXMOX_NODE - Proxmox node name (default: strongmad)
#   TEMPLATE_VMID - VM ID for template (default: 9000)

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# Configuration - derive from TF vars or use defaults
# Extract host from API URL (https://host:8006/api2/json -> host)
if [ -n "${TF_VAR_proxmox_api_url:-}" ]; then
  PROXMOX_HOST="${PROXMOX_HOST:-$(echo "$TF_VAR_proxmox_api_url" | sed -E 's|https?://([^:/]+).*|\1|')}"
else
  PROXMOX_HOST="${PROXMOX_HOST:-}"
fi

PROXMOX_USER="${PROXMOX_USER:-root}"
PROXMOX_STORAGE="${PROXMOX_STORAGE:-${TF_VAR_vm_storage:-local-lvm}}"
PROXMOX_NODE="${PROXMOX_NODE:-strongmad}"
TEMPLATE_VMID="${TEMPLATE_VMID:-9000}"
TEMPLATE_NAME="${TEMPLATE_NAME:-nixos-template}"

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

echo "=== NixOS Image Upload Script ==="
echo ""
log_info "Proxmox Host: $PROXMOX_HOST"
log_info "Proxmox Node: $PROXMOX_NODE"
log_info "Storage: $PROXMOX_STORAGE"
log_info "Template VM ID: $TEMPLATE_VMID"
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

# Step 3: Upload to Proxmox
log_info "Uploading to Proxmox host $PROXMOX_HOST..."
scp -o StrictHostKeyChecking=accept-new "$VMA_FILE" "${PROXMOX_USER}@${PROXMOX_HOST}:/tmp/nixos.vma"

# Step 4: Restore VMA as template on Proxmox
log_info "Creating template VM (ID: $TEMPLATE_VMID)..."

ssh -o StrictHostKeyChecking=accept-new "${PROXMOX_USER}@${PROXMOX_HOST}" bash <<EOF
set -e

# Remove existing template if present
if qm status $TEMPLATE_VMID &>/dev/null; then
  echo "Removing existing template..."
  qm destroy $TEMPLATE_VMID --purge || true
fi

# Restore VMA to new VM
echo "Restoring VMA..."
qmrestore /tmp/nixos.vma $TEMPLATE_VMID --storage $PROXMOX_STORAGE

# Configure VM
echo "Configuring VM..."
qm set $TEMPLATE_VMID --name "$TEMPLATE_NAME"
qm set $TEMPLATE_VMID --description "NixOS base image for Colmena-managed VMs. Built: $(date -Iseconds)"
qm set $TEMPLATE_VMID --tags "template,nixos,tofu"
qm set $TEMPLATE_VMID --agent enabled=1
qm set $TEMPLATE_VMID --serial0 socket
qm set $TEMPLATE_VMID --vga std

# Convert to template
echo "Converting to template..."
qm template $TEMPLATE_VMID

# Cleanup
rm -f /tmp/nixos.vma

echo "Template created successfully!"
EOF

echo ""
echo "=== Upload Complete ==="
echo ""
log_info "Template ID: $TEMPLATE_VMID"
log_info "Template Name: $TEMPLATE_NAME"
log_info "Storage: $PROXMOX_STORAGE"
echo ""
log_info "You can now use this template in OpenTofu."
log_info "NixOS VMs will be cloned from this template."
