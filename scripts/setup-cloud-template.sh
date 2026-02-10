#!/usr/bin/env bash
# One-time setup: Download Debian cloud image and create Proxmox VM template
#
# Usage: ./scripts/setup-cloud-template.sh
#
# This creates a Debian 12 cloud image template on Proxmox that supports
# cloud-init for SSH key and IP injection. VMs cloned from this template
# are then converted to NixOS via nixos-anywhere.
#
# Environment variables (from .env via direnv):
#   TF_VAR_proxmox_api_url - Proxmox API URL (used to derive host)
#   PROXMOX_HOST - Override Proxmox host (optional)
#   PROXMOX_USER - SSH user for Proxmox (default: root)
#   PROXMOX_STORAGE - Storage for template disk (default: local-lvm)
#   TEMPLATE_VMID - VM ID for the template (default: 9000)

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }
log_step() { echo -e "${BLUE}[STEP]${NC} $1"; }

# Configuration
if [ -n "${TF_VAR_proxmox_api_url:-}" ]; then
  PROXMOX_HOST="${PROXMOX_HOST:-$(echo "$TF_VAR_proxmox_api_url" | sed -E 's|https?://([^:/]+).*|\1|')}"
else
  PROXMOX_HOST="${PROXMOX_HOST:-}"
fi

PROXMOX_USER="${PROXMOX_USER:-root}"
PROXMOX_STORAGE="${PROXMOX_STORAGE:-local-lvm}"
TEMPLATE_VMID="${TEMPLATE_VMID:-9000}"
TEMPLATE_NAME="debian-cloud-template"
DEBIAN_IMAGE_URL="https://cloud.debian.org/images/cloud/bookworm/latest/debian-12-generic-amd64.qcow2"
DEBIAN_IMAGE_FILE="debian-12-generic-amd64.qcow2"

# Validate required config
if [ -z "$PROXMOX_HOST" ]; then
  log_error "PROXMOX_HOST not set. Set TF_VAR_proxmox_api_url or PROXMOX_HOST environment variable."
  exit 1
fi

echo "=== Debian Cloud Template Setup ==="
echo ""
log_info "Proxmox Host: $PROXMOX_HOST"
log_info "Storage: $PROXMOX_STORAGE"
log_info "Template VMID: $TEMPLATE_VMID"
log_info "Image: $DEBIAN_IMAGE_URL"
echo ""

# Step 1: Download Debian cloud image to Proxmox host
log_step "Step 1: Downloading Debian cloud image to Proxmox..."
ssh -o StrictHostKeyChecking=accept-new "${PROXMOX_USER}@${PROXMOX_HOST}" bash <<EOF
set -e

cd /tmp
if [ -f "$DEBIAN_IMAGE_FILE" ]; then
  echo "Image already exists at /tmp/$DEBIAN_IMAGE_FILE, reusing..."
else
  echo "Downloading $DEBIAN_IMAGE_URL..."
  wget -q --show-progress "$DEBIAN_IMAGE_URL" -O "$DEBIAN_IMAGE_FILE"
fi
EOF

# Step 2: Create template VM
log_step "Step 2: Creating template VM..."
ssh -o StrictHostKeyChecking=accept-new "${PROXMOX_USER}@${PROXMOX_HOST}" bash <<EOF
set -e

# Remove existing template if present
if qm status $TEMPLATE_VMID &>/dev/null; then
  echo "Removing existing template $TEMPLATE_VMID..."
  qm destroy $TEMPLATE_VMID --purge || true
fi

# Create VM
echo "Creating VM $TEMPLATE_VMID..."
qm create $TEMPLATE_VMID \
  --name "$TEMPLATE_NAME" \
  --ostype l26 \
  --agent enabled=1 \
  --bios seabios \
  --machine pc \
  --cpu host \
  --cores 2 \
  --memory 2048 \
  --net0 virtio,bridge=vmbr0 \
  --serial0 socket \
  --vga serial0 \
  --tags "template,debian,cloud-init" \
  --description "Debian 12 cloud image template for nixos-anywhere. Created: \$(date -Iseconds)"

# Import disk
echo "Importing disk to $PROXMOX_STORAGE..."
qm importdisk $TEMPLATE_VMID "/tmp/$DEBIAN_IMAGE_FILE" $PROXMOX_STORAGE

# Attach disk and configure boot
echo "Configuring VM..."
qm set $TEMPLATE_VMID --virtio0 ${PROXMOX_STORAGE}:vm-${TEMPLATE_VMID}-disk-0
qm set $TEMPLATE_VMID --boot order=virtio0
qm set $TEMPLATE_VMID --ide2 ${PROXMOX_STORAGE}:cloudinit

# Convert to template
echo "Converting to template..."
qm template $TEMPLATE_VMID

echo ""
echo "Template $TEMPLATE_VMID created successfully!"
EOF

# Step 3: Clean up
log_step "Step 3: Cleaning up..."
ssh -o StrictHostKeyChecking=accept-new "${PROXMOX_USER}@${PROXMOX_HOST}" "rm -f /tmp/$DEBIAN_IMAGE_FILE"

echo ""
echo "=== Setup Complete ==="
echo ""
log_info "Template VMID: $TEMPLATE_VMID"
log_info "Next steps:"
echo "  1. Run: tofu apply                                    # Clone VMs from template"
echo "  2. Run: ./scripts/deploy.sh --nixos-anywhere          # Install NixOS on all VMs"
echo "  3. Run: colmena apply                                 # Deploy NixOS configs"
echo ""
