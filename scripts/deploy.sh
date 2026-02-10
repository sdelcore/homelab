#!/usr/bin/env bash
# Full deployment script: Provision VMs -> nixos-anywhere -> Colmena
#
# Usage: ./scripts/deploy.sh [options]
#
# Options:
#   --nixos-anywhere          Run nixos-anywhere on ALL hosts (wipes disks!)
#   --nixos-anywhere-on HOST  Run nixos-anywhere on a single host
#   --skip-tofu               Skip OpenTofu provisioning
#   --skip-colmena            Skip Colmena deployment
#   --tofu-only               Only run OpenTofu, then exit
#   --colmena-only            Only run Colmena, then exit
#   -h, --help                Show this help message

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
HOSTS_JSON="$PROJECT_ROOT/nixos/hosts.json"

SKIP_TOFU=false
SKIP_COLMENA=false
TOFU_ONLY=false
COLMENA_ONLY=false
NIXOS_ANYWHERE=false
NIXOS_ANYWHERE_HOST=""

# Parse args
while [[ $# -gt 0 ]]; do
  case $1 in
    --nixos-anywhere) NIXOS_ANYWHERE=true ;;
    --nixos-anywhere-on)
      NIXOS_ANYWHERE=true
      NIXOS_ANYWHERE_HOST="$2"
      shift
      ;;
    --skip-tofu) SKIP_TOFU=true ;;
    --skip-colmena) SKIP_COLMENA=true ;;
    --tofu-only) TOFU_ONLY=true ;;
    --colmena-only) COLMENA_ONLY=true ;;
    -h|--help)
      echo "Usage: $0 [options]"
      echo ""
      echo "Options:"
      echo "  --nixos-anywhere          Run nixos-anywhere on ALL hosts (wipes disks!)"
      echo "  --nixos-anywhere-on HOST  Run nixos-anywhere on a single host"
      echo "  --skip-tofu               Skip OpenTofu provisioning"
      echo "  --skip-colmena            Skip Colmena deployment"
      echo "  --tofu-only               Only run OpenTofu, then exit"
      echo "  --colmena-only            Only run Colmena, then exit"
      echo "  -h, --help                Show this help message"
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
if [ "$TOFU_ONLY" = true ]; then
  SKIP_COLMENA=true
fi
if [ "$COLMENA_ONLY" = true ]; then
  SKIP_TOFU=true
fi

# ---------------------------------------------------------------------------
# Helper: wait for SSH connectivity on a host
# ---------------------------------------------------------------------------
wait_for_ssh() {
  local host=$1
  local max_attempts=${2:-30}
  log_info "Waiting for $host..."
  for i in $(seq 1 "$max_attempts"); do
    if ssh -o ConnectTimeout=5 -o StrictHostKeyChecking=accept-new -o BatchMode=yes "root@$host" true 2>/dev/null; then
      log_info "$host is ready"
      return 0
    fi
    if [ "$i" -eq "$max_attempts" ]; then
      log_warn "$host not responding after $((max_attempts * 10 / 60)) minutes, continuing anyway..."
      return 1
    fi
    sleep 10
  done
}

# ---------------------------------------------------------------------------
# Helper: run nixos-anywhere on a single host
# ---------------------------------------------------------------------------
run_nixos_anywhere() {
  local name=$1
  local ip=$2

  log_info "Installing NixOS on $name ($ip)..."

  # Remove old host key (host key changes after nixos-anywhere)
  ssh-keygen -R "$ip" 2>/dev/null || true

  nixos-anywhere --flake "$PROJECT_ROOT/nixos#${name}" "root@${ip}"
}

# ---------------------------------------------------------------------------
# Load host list from hosts.json (single source of truth)
# ---------------------------------------------------------------------------
mapfile -t ALL_HOST_NAMES < <(jq -r '.hosts | keys[]' "$HOSTS_JSON")
mapfile -t ALL_HOST_IPS < <(jq -r '.hosts | to_entries[] | .value.ip' "$HOSTS_JSON")
mapfile -t GPU_HOST_IPS < <(jq -r '.hosts | to_entries[] | select(.value.gpu) | .value.ip' "$HOSTS_JSON")
mapfile -t GPU_HOST_NAMES < <(jq -r '.hosts | to_entries[] | select(.value.gpu) | .key' "$HOSTS_JSON")

echo "=============================================="
echo "       Homelab Deployment"
echo "=============================================="
echo ""

# Step 1: Provision VMs with OpenTofu
if [ "$SKIP_TOFU" = false ]; then
  log_step "Step 1: Provisioning VMs with OpenTofu..."
  cd "$PROJECT_ROOT/infrastructure"
  tofu init -upgrade
  tofu apply -auto-approve
  cd "$PROJECT_ROOT"
  echo ""
else
  log_info "Step 1: Skipping OpenTofu"
fi

# Step 2: Wait for VMs to boot (Debian cloud image via cloud-init)
if [ "$NIXOS_ANYWHERE" = true ] || [ "$SKIP_COLMENA" = false ]; then
  log_step "Step 2: Waiting for VMs to boot..."
  for host in "${ALL_HOST_IPS[@]}"; do
    wait_for_ssh "$host"
  done
  echo ""
fi

# Step 3: nixos-anywhere (install NixOS over Debian)
if [ "$NIXOS_ANYWHERE" = true ]; then
  echo ""
  log_warn "=============================================="
  log_warn "  nixos-anywhere will WIPE DISKS on target VMs!"
  log_warn "=============================================="

  if [ -n "$NIXOS_ANYWHERE_HOST" ]; then
    log_warn "  Target: $NIXOS_ANYWHERE_HOST"
  else
    log_warn "  Target: ALL hosts (${ALL_HOST_NAMES[*]})"
  fi

  echo ""
  read -rp "Are you sure? Type 'yes' to continue: " confirm
  if [ "$confirm" != "yes" ]; then
    log_error "Aborted."
    exit 1
  fi
  echo ""

  log_step "Step 3: Running nixos-anywhere..."

  if [ -n "$NIXOS_ANYWHERE_HOST" ]; then
    # Single host
    ip=$(jq -r ".hosts[\"$NIXOS_ANYWHERE_HOST\"].ip" "$HOSTS_JSON")
    if [ "$ip" = "null" ] || [ -z "$ip" ]; then
      log_error "Host '$NIXOS_ANYWHERE_HOST' not found in hosts.json"
      exit 1
    fi
    run_nixos_anywhere "$NIXOS_ANYWHERE_HOST" "$ip"
  else
    # All hosts
    for idx in "${!ALL_HOST_NAMES[@]}"; do
      run_nixos_anywhere "${ALL_HOST_NAMES[$idx]}" "${ALL_HOST_IPS[$idx]}"
    done
  fi

  echo ""
  log_step "Step 3b: Waiting for NixOS VMs to reboot..."

  if [ -n "$NIXOS_ANYWHERE_HOST" ]; then
    ip=$(jq -r ".hosts[\"$NIXOS_ANYWHERE_HOST\"].ip" "$HOSTS_JSON")
    # Remove old host key again (nixos-anywhere generates new keys)
    ssh-keygen -R "$ip" 2>/dev/null || true
    wait_for_ssh "$ip"
  else
    for host in "${ALL_HOST_IPS[@]}"; do
      ssh-keygen -R "$host" 2>/dev/null || true
      wait_for_ssh "$host"
    done
  fi
  echo ""
fi

# Step 4: Deploy NixOS configurations with Colmena
if [ "$SKIP_COLMENA" = false ]; then
  log_step "Step 4: Deploying NixOS configurations with Colmena..."
  cd "$PROJECT_ROOT/nixos"
  colmena apply
  cd "$PROJECT_ROOT"
  echo ""
fi

# Step 5: Reboot GPU VMs if nouveau is loaded (first-boot only)
if [ "$SKIP_COLMENA" = false ] && [ ${#GPU_HOST_IPS[@]} -gt 0 ]; then
  log_step "Step 5: Checking GPU VMs for nouveau (first-boot fix)..."
  REBOOT_NAMES=()
  for idx in "${!GPU_HOST_IPS[@]}"; do
    host="${GPU_HOST_IPS[$idx]}"
    name="${GPU_HOST_NAMES[$idx]}"
    if ! ssh -o ConnectTimeout=5 -o BatchMode=yes "root@$host" "nvidia-smi" &>/dev/null; then
      log_warn "$name ($host): nvidia-smi failed — rebooting to unload nouveau..."
      ssh -o ConnectTimeout=5 -o BatchMode=yes "root@$host" "reboot" 2>/dev/null || true
      REBOOT_NAMES+=("$name")
    else
      log_info "$name ($host): nvidia-smi OK"
    fi
  done

  if [ ${#REBOOT_NAMES[@]} -gt 0 ]; then
    log_info "Waiting for rebooted GPU VMs..."
    sleep 15
    for idx in "${!GPU_HOST_IPS[@]}"; do
      name="${GPU_HOST_NAMES[$idx]}"
      for rn in "${REBOOT_NAMES[@]}"; do
        if [ "$name" = "$rn" ]; then
          wait_for_ssh "${GPU_HOST_IPS[$idx]}"
          break
        fi
      done
    done

    log_step "Step 5b: Re-applying Colmena to rebooted GPU VMs..."
    cd "$PROJECT_ROOT/nixos"
    COLMENA_TARGETS=$(printf " --on %s" "${REBOOT_NAMES[@]}")
    colmena apply $COLMENA_TARGETS
    cd "$PROJECT_ROOT"
    echo ""
  else
    log_info "All GPU VMs have NVIDIA drivers loaded"
  fi
else
  if [ "$SKIP_COLMENA" = false ]; then
    log_info "Step 5: No GPU VMs configured, skipping"
  fi
fi

echo "=============================================="
echo "       Deployment Complete!"
echo "=============================================="
echo ""
log_info "NixOS VMs:"
jq -r '.hosts | to_entries[] | "  \(.key): http://\(.value.ip) (\(.value.domain))"' "$HOSTS_JSON"
echo ""
log_info "Management commands:"
echo "  colmena apply              # Deploy NixOS configs"
echo "  colmena apply --on arr     # Deploy to specific host"
echo "  colmena apply --on @media  # Deploy to hosts by tag"
echo "  colmena upload-keys        # Update secrets only"
echo "  colmena build              # Build without deploying"
echo ""
