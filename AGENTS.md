# AGENTS.md

Instructions for AI coding agents working in this repository.

## Project Overview

Infrastructure-as-code for deploying NixOS Docker hosts on Proxmox using:
- **OpenTofu**: VM provisioning (clones Debian cloud image templates)
- **nixos-anywhere**: Installs NixOS over SSH onto Debian VMs (uses disko for partitioning)
- **NixOS + Colmena**: Configuration management for all VMs
- **1Password**: Secrets management via `op` CLI

## Build/Deploy Commands

```bash
# Enter development environment (required - loads tools + 1Password secrets)
direnv allow

# Full deployment
./scripts/deploy.sh                                  # tofu + colmena (daily use)
./scripts/deploy.sh --nixos-anywhere                 # tofu + nixos-anywhere ALL + colmena
./scripts/deploy.sh --nixos-anywhere-on tools        # tofu + nixos-anywhere single host + colmena
./scripts/deploy.sh --colmena-only                   # NixOS configs only
./scripts/deploy.sh --tofu-only                      # VM provisioning only

# One-time setup: create Debian cloud image template on Proxmox
./scripts/setup-cloud-template.sh

# OpenTofu (VM provisioning) - run from infrastructure/
tofu init                              # Initialize providers
tofu plan                              # Preview changes
tofu apply                             # Apply all changes
tofu apply -target='proxmox_virtual_environment_vm.nixos_vm["arr"]'  # Single VM
tofu apply -replace='proxmox_virtual_environment_vm.nixos_vm["arr"]' # Recreate VM

# Colmena (NixOS configuration) - run from nixos/
colmena build                          # Build without deploying
colmena apply                          # Deploy to all hosts
colmena apply --on arr                 # Deploy to specific host
colmena apply --on @media              # Deploy by tag
colmena upload-keys                    # Update secrets only

# nixos-anywhere (install NixOS on a Debian VM)
nixos-anywhere --flake ./nixos#tools root@10.0.0.21

# Build NixOS config for a host (verify it compiles)
nix build ./nixos#nixosConfigurations.tools.config.system.build.toplevel
```

## Testing & Validation

No automated test suite exists. Validation is done via:
```bash
tofu plan                              # Check OpenTofu changes
tofu validate                          # Validate HCL syntax
colmena build                          # Verify NixOS configs compile
nix flake check                        # Check flake validity
```

## Code Style Guidelines

### Shell Scripts (.sh)
- Shebang: `#!/usr/bin/env bash`
- Strict mode: `set -euo pipefail` at top of script
- Color-coded logging functions:
  ```bash
  log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
  log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
  log_error() { echo -e "${RED}[ERROR]${NC} $1"; }
  log_step() { echo -e "${BLUE}[STEP]${NC} $1"; }
  ```
- Script directory detection: `SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"`
- Use heredocs for multi-line SSH commands
- Parse args with `while [[ $# -gt 0 ]]; do case $1 in ... esac; shift; done`

### OpenTofu/Terraform (.tf)
- Section headers with `# =====` separator lines
- Group related resources under descriptive `# -----------` subsection headers
- Use `locals {}` for VM definitions and shared configuration
- Naming: `proxmox_virtual_environment_vm.nixos_vm["name"]`
- Always include `description` attributes for resources
- Use `lifecycle { ignore_changes = [...] }` for fields managed elsewhere
- Template files in `templates/` with `.tpl` extension

### Nix (.nix)
- Section headers with `# ============` separator lines
- Module structure:
  ```nix
  { config, pkgs, lib, ... }:
  with lib;
  let cfg = config.moduleName; in
  {
    options.moduleName = { ... };
    config = mkIf cfg.enable { ... };
  }
  ```
- Use `mkOption` with `types.*` and `description`
- Use `mkEnableOption` for boolean enable flags
- Pass shared config via `specialArgs` in flake
- Use `mkIf`, `mkMerge`, `mkForce` for conditional config
- Comments for non-obvious configurations

### Docker Compose (compose.yml)
- Comment headers above each service explaining purpose
- Traefik labels for routing: `traefik.http.routers.<name>.rule=Host(...)`
- Homepage labels for dashboard discovery: `homepage.group`, `homepage.name`, etc.
- Environment defaults: `${VAR:-default}`
- NFS volumes for shared data, local `./config/` for per-service state
- Networks: Use named bridge networks per stack
- Use `pull_policy: always` for services using `:latest` tag to auto-pull updates on restart

## File Organization

| Directory | Purpose |
|-----------|---------|
| `nixos/hosts.json` | **Single source of truth** for all VM definitions |
| `infrastructure/` | OpenTofu IaC (VM provisioning) |
| `infrastructure/templates/` | Cloud-init templates (reference only, not deployed) |
| `nixos/` | NixOS + Colmena configuration |
| `nixos/hosts/` | Per-host NixOS configurations |
| `nixos/modules/` | Reusable NixOS modules (base, disko, docker-stack, etc.) |
| `nixos/stacks/` | Docker Compose stacks (deployed via Colmena) |
| `scripts/` | Deployment automation scripts |
| `docs/` | Additional documentation (cloud-init troubleshooting, etc.) |

## Naming Conventions

- **VM names**: lowercase, short (arr, tools, nvr, aria)
- **Stack names**: match VM names
- **NixOS hosts**: `nixos/hosts/<vmname>.nix`
- **1Password secrets**: `env-<stackname>-stack` in Infrastructure vault
- **IP addresses**: 10.0.0.XX/24 (see hosts.json for allocations)
- **MAC addresses**: `BC:24:11:00:00:XX` prefix

## Adding a New NixOS VM

1. Add VM to `nixos/hosts.json`:
   ```json
   "newvm": {
     "ip": "10.0.0.XX",
     "mac": "BC:24:11:00:00:XX",
     "node": "strongmad",
     "vmId": 205,
     "cores": 2,
     "memory": 2048,
     "disk": 30,
     "domain": "newvm.tap",
     "tags": ["docker", "nixos"],
     "gpu": false
   }
   ```

2. Create host config at `nixos/hosts/newvm.nix`

3. Create stack at `nixos/stacks/newvm/compose.yml`

4. Create 1Password secret: `op item create --category="Secure Note" --title="env-newvm-stack" --vault="Infrastructure" 'notesPlain=KEY=value'`

5. Deploy:
   ```bash
   tofu apply                                          # Provision VM (Debian)
   ./scripts/deploy.sh --nixos-anywhere-on newvm       # Install NixOS + configure
   ```

## Secrets Management

- Colmena `deployment.keys` with `keyCommand` using `op read`
- Never commit `.env` files - use `.env.example` templates
- Reference format: `op://Infrastructure/env-<stack>-stack/notesPlain`

## Key Architecture Patterns

- **Single source of truth**: All VM config (IP, MAC, resources) defined in `nixos/hosts.json`
- **Debian template + nixos-anywhere**: VMs boot Debian via cloud-init, then nixos-anywhere installs NixOS over SSH
- **Disko**: Declarative disk partitioning (GPT + BIOS boot + ext4 root) shared across all VMs
- **Shared NixOS modules**: `sharedModules` and `mkHostConfig` in flake.nix are used by both `nixosConfigurations` (nixos-anywhere) and `colmenaHive`
- **Traefik per VM**: Each stack runs its own Traefik for subdomain routing
- **NFS backup**: Configs at `/opt/stacks/<stack>/config/` synced hourly to NFS
- **Docker TCP**: Enable on VMs needing remote discovery (Homepage)
- **GPU VMs**: Require `gpu: true` and `gpuId` in hosts.json

## Common Gotchas

- Cloud-init only runs on first boot; recreate VM for cloud-init config changes
- nixos-anywhere wipes disks — use with caution on existing VMs
- After nixos-anywhere, host SSH keys change — `ssh-keygen -R <ip>` (deploy.sh does this automatically)
- NVIDIA GPU passthrough requires `rombar = false`
- After IP reuse, clear SSH known_hosts: `ssh-keygen -R <ip>`
- New files in nixos/ must be `git add`ed before `colmena build` (Nix flakes only see tracked files)
- `networking.usePredictableInterfaceNames = false` is in `base.nix` — required for `eth0` references

## Stack-Specific Configuration

### Mem Stack (aria)
The mem video processing stack requires special configuration for RTMP streaming:
- Set `RTMP_HOST` environment variable to the external hostname (e.g., `aria.tap`)
- Configure `streaming.rtmp.host` in `config/mem/config.yaml`
- This ensures OBS receives correct RTMP URLs for connecting from outside Docker network
- Uses `pull_policy: always` to auto-update images when containers restart
