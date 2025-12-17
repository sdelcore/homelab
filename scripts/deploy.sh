#!/usr/bin/env bash
# Full deployment script: Build image -> Upload -> Provision -> Configure
#
# Usage: ./scripts/deploy.sh [options]
#
# Options:
#   --skip-image     Skip building and uploading NixOS image
#   --skip-tofu      Skip OpenTofu provisioning
#   --skip-colmena   Skip Colmena deployment
#   --image-only     Only build and upload image, then exit
#   --tofu-only      Only run OpenTofu, then exit
#   --colmena-only   Only run Colmena, then exit
#   -h, --help       Show this help message

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

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

SKIP_IMAGE=false
SKIP_TOFU=false
SKIP_COLMENA=false
IMAGE_ONLY=false
TOFU_ONLY=false
COLMENA_ONLY=false

# Parse args
while [[ $# -gt 0 ]]; do
  case $1 in
    --skip-image) SKIP_IMAGE=true ;;
    --skip-tofu) SKIP_TOFU=true ;;
    --skip-colmena) SKIP_COLMENA=true ;;
    --image-only) IMAGE_ONLY=true ;;
    --tofu-only) TOFU_ONLY=true ;;
    --colmena-only) COLMENA_ONLY=true ;;
    -h|--help)
      echo "Usage: $0 [options]"
      echo ""
      echo "Options:"
      echo "  --skip-image     Skip building and uploading NixOS image"
      echo "  --skip-tofu      Skip OpenTofu provisioning"
      echo "  --skip-colmena   Skip Colmena deployment"
      echo "  --image-only     Only build and upload image, then exit"
      echo "  --tofu-only      Only run OpenTofu, then exit"
      echo "  --colmena-only   Only run Colmena, then exit"
      echo "  -h, --help       Show this help message"
      exit 0
      ;;
    *)
      log_error "Unknown option: $1"
      exit 1
      ;;
  esac
  shift
done

# Handle *-only flags
if [ "$IMAGE_ONLY" = true ]; then
  SKIP_TOFU=true
  SKIP_COLMENA=true
fi
if [ "$TOFU_ONLY" = true ]; then
  SKIP_IMAGE=true
  SKIP_COLMENA=true
fi
if [ "$COLMENA_ONLY" = true ]; then
  SKIP_IMAGE=true
  SKIP_TOFU=true
fi

echo "=============================================="
echo "       Homelab Deployment"
echo "=============================================="
echo ""

# Step 1: Build and upload NixOS image
if [ "$SKIP_IMAGE" = false ]; then
  log_step "Step 1: Building and uploading NixOS image..."
  "$SCRIPT_DIR/upload-nixos-image.sh"
  echo ""
else
  log_info "Step 1: Skipping image build/upload"
fi

# Step 2: Provision VMs with OpenTofu
if [ "$SKIP_TOFU" = false ]; then
  log_step "Step 2: Provisioning VMs with OpenTofu..."
  cd "$PROJECT_ROOT/infrastructure"
  tofu init -upgrade
  tofu apply -auto-approve
  cd "$PROJECT_ROOT"
  echo ""
else
  log_info "Step 2: Skipping OpenTofu"
fi

# Step 3: Wait for VMs to boot
if [ "$SKIP_COLMENA" = false ]; then
  log_step "Step 3: Waiting for NixOS VMs to boot..."

  NIXOS_HOSTS=("10.0.0.20" "10.0.0.21")
  for host in "${NIXOS_HOSTS[@]}"; do
    log_info "Waiting for $host..."
    for i in {1..30}; do
      if ssh -o ConnectTimeout=5 -o StrictHostKeyChecking=accept-new -o BatchMode=yes "root@$host" true 2>/dev/null; then
        log_info "$host is ready"
        break
      fi
      if [ $i -eq 30 ]; then
        log_warn "$host not responding after 5 minutes, continuing anyway..."
      fi
      sleep 10
    done
  done
  echo ""
fi

# Step 4: Deploy NixOS configurations with Colmena
if [ "$SKIP_COLMENA" = false ]; then
  log_step "Step 4: Deploying NixOS configurations with Colmena..."
  cd "$PROJECT_ROOT/nixos"
  colmena apply
  cd "$PROJECT_ROOT"
  echo ""
else
  log_info "Step 4: Skipping Colmena"
fi

echo "=============================================="
echo "       Deployment Complete!"
echo "=============================================="
echo ""
log_info "NixOS VMs:"
echo "  arr:   http://10.0.0.20"
echo "         - traefik.arr.tap"
echo "         - sonarr.arr.tap, radarr.arr.tap, etc."
echo ""
echo "  tools: http://10.0.0.21"
echo "         - home.tools.tap (Homepage)"
echo "         - pdf.tools.tap (Stirling PDF)"
echo ""
log_info "Ubuntu VM:"
echo "  portainer: http://10.0.0.22"
echo "             - portainer.portainer.tap"
echo ""
log_info "Management commands:"
echo "  colmena apply              # Deploy NixOS configs"
echo "  colmena apply --on arr     # Deploy to specific host"
echo "  colmena apply --on @media  # Deploy to hosts by tag"
echo "  colmena upload-keys        # Update secrets only"
echo "  colmena build              # Build without deploying"
echo ""
