# Project orchestration for NixOS homelab on Proxmox

set shell := ["bash", "-euo", "pipefail", "-c"]

# Directories
nixos_dir := justfile_directory() / "nixos"
infra_dir := justfile_directory() / "infrastructure"
artifacts_dir := justfile_directory() / "artifacts"
hosts_json := artifacts_dir / "hosts.json"

# List available commands
default:
    @just --list

# ============================================================
# Helper recipes
# ============================================================

# Look up a host's IP from hosts.json (stdout: IP, stderr: errors)
_get-ip host:
    #!/usr/bin/env bash
    set -euo pipefail
    if [[ ! -f "{{ hosts_json }}" ]]; then
        echo "ERROR: {{ hosts_json }} not found. Run 'just generate' first." >&2
        exit 1
    fi
    ip=$(jq -r '.hosts["{{ host }}"].ip' "{{ hosts_json }}")
    if [[ "$ip" == "null" || -z "$ip" ]]; then
        echo "ERROR: Host '{{ host }}' not found in {{ hosts_json }}" >&2
        exit 1
    fi
    echo "$ip"

# Wait for a host to become reachable via SSH
_wait-for-host host ip:
    #!/usr/bin/env bash
    set -euo pipefail
    echo "Waiting for {{ host }} ({{ ip }}) to become reachable..."
    for i in $(seq 1 30); do
        if ssh -o ConnectTimeout=5 -o StrictHostKeyChecking=accept-new -o BatchMode=yes "root@{{ ip }}" true 2>/dev/null; then
            echo "{{ host }} is ready"
            exit 0
        fi
        sleep 10
    done
    echo "WARNING: {{ host }} ({{ ip }}) did not become reachable after 5 minutes"

# ============================================================
# Generate & validate
# ============================================================

# Generate artifacts/hosts.json from Nix host definitions
generate:
    nix eval --json 'path:{{ nixos_dir }}#terraformHosts' | jq . > {{ hosts_json }}
    @echo "Generated {{ hosts_json }}"

# Validate artifacts/hosts.json exists and is valid JSON
validate:
    @test -f {{ hosts_json }} || { echo "ERROR: {{ hosts_json }} not found. Run 'just generate' first."; exit 1; }
    @jq empty {{ hosts_json }} && echo "{{ hosts_json }} is valid JSON"

# ============================================================
# Secrets & infrastructure
# ============================================================

# Generate secrets.auto.tfvars from 1Password
init-secrets:
    #!/usr/bin/env bash
    set -euo pipefail
    echo "Generating secrets from 1Password..."
    cat > "{{ infra_dir }}/secrets.auto.tfvars" <<EOF
    proxmox = {
      api_url          = "$(op read 'op://Infrastructure/Proxmox/strongmad/url')"
      api_token_id     = "$(op read 'op://Infrastructure/Proxmox/token_id')"
      api_token_secret = "$(op read 'op://Infrastructure/Proxmox/credential')"
      tls_insecure     = true
    }
    EOF
    echo "Generated {{ infra_dir }}/secrets.auto.tfvars"

# Initialize OpenTofu providers
init: validate
    @echo "Initializing OpenTofu..."
    cd {{ infra_dir }} && tofu init

# Preview OpenTofu changes
plan: validate
    cd {{ infra_dir }} && tofu plan

# Apply OpenTofu changes
tofu: validate
    cd {{ infra_dir }} && tofu apply

# ============================================================
# nixos-anywhere (provision)
# ============================================================

# Core nixos-anywhere provision for a single host
_provision host:
    #!/usr/bin/env bash
    set -euo pipefail
    ip=$(just _get-ip "{{ host }}")
    ssh-keygen -R "$ip" 2>/dev/null || true
    echo "Provisioning NixOS on {{ host }} ($ip)..."
    nixos-anywhere --flake "{{ nixos_dir }}#{{ host }}" "root@${ip}"
    ssh-keygen -R "$ip" 2>/dev/null || true

# Provision a host with NixOS via nixos-anywhere (wipes disk)
provision host:
    #!/usr/bin/env bash
    set -euo pipefail
    just _provision "{{ host }}"
    ip=$(just _get-ip "{{ host }}")
    just _wait-for-host "{{ host }}" "$ip"

# Provision all hosts with NixOS via nixos-anywhere (wipes all disks)
provision-all:
    #!/usr/bin/env bash
    set -euo pipefail
    for name in $(jq -r '.hosts | keys[]' "{{ hosts_json }}"); do
        just _provision "$name"
        ip=$(just _get-ip "$name")
        just _wait-for-host "$name" "$ip"
    done

# ============================================================
# Colmena (deploy)
# ============================================================

# Deploy NixOS configurations via Colmena (with GPU nouveau fix)
deploy: validate
    #!/usr/bin/env bash
    set -euo pipefail
    echo "Deploying NixOS configurations with Colmena..."
    cd "{{ nixos_dir }}" && colmena apply

    # GPU nouveau fix: reboot if nvidia-smi fails
    mapfile -t gpu_hosts < <(jq -r '.hosts | to_entries[] | select(.value.gpu) | .key' "{{ hosts_json }}")

    if [[ ${#gpu_hosts[@]} -eq 0 ]]; then
        echo "No GPU hosts to check"
        exit 0
    fi

    echo "Checking GPU hosts for nouveau (first-boot fix)..."
    reboot_hosts=()
    for name in "${gpu_hosts[@]}"; do
        ip=$(just _get-ip "$name")
        if ! ssh -o ConnectTimeout=5 -o BatchMode=yes "root@$ip" "nvidia-smi" &>/dev/null; then
            echo "WARNING: $name ($ip): nvidia-smi failed — rebooting..."
            ssh -o ConnectTimeout=5 -o BatchMode=yes "root@$ip" "reboot" 2>/dev/null || true
            reboot_hosts+=("$name")
        else
            echo "$name ($ip): nvidia-smi OK"
        fi
    done

    if [[ ${#reboot_hosts[@]} -gt 0 ]]; then
        sleep 15
        for name in "${reboot_hosts[@]}"; do
            ip=$(just _get-ip "$name")
            just _wait-for-host "$name" "$ip"
        done
        echo "Re-applying Colmena to rebooted GPU hosts..."
        targets=$(printf " --on %s" "${reboot_hosts[@]}")
        cd "{{ nixos_dir }}" && colmena apply $targets
    else
        echo "All GPU hosts have NVIDIA drivers loaded"
    fi

# Deploy NixOS configuration to a specific host
deploy-on host:
    cd {{ nixos_dir }} && colmena apply --on {{ host }}

# Upload secrets to all hosts
upload-keys:
    cd {{ nixos_dir }} && colmena upload-keys

# Show host IPs and domains
info: validate
    @echo ""
    @echo "NixOS Hosts:"
    @jq -r '.hosts | to_entries[] | "  \(.key): \(.value.ip) (\(.value.domain))"' {{ hosts_json }}
    @echo ""
