# AGENTS.md

Instructions for AI coding agents working in this repository.

## Project Overview

Infrastructure-as-code for deploying NixOS Docker hosts on Proxmox using:
- **OpenTofu**: VM provisioning (clones NixOS templates)
- **NixOS + Colmena**: Configuration management for all VMs
- **1Password**: Secrets management via `op` CLI

## Build/Deploy Commands

```bash
# Enter development environment (required - loads tools + 1Password secrets)
direnv allow

# Full deployment
./scripts/deploy.sh                    # Image + tofu + colmena
./scripts/deploy.sh --colmena-only     # NixOS configs only
./scripts/deploy.sh --tofu-only        # VM provisioning only
./scripts/deploy.sh --image-only       # NixOS image build/upload only

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

# NixOS image
cd nixos && nix build .#proxmox-image  # Build Proxmox image
./scripts/upload-nixos-image.sh        # Upload to Proxmox as template
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

## File Organization

| Directory | Purpose |
|-----------|---------|
| `nixos/hosts.json` | **Single source of truth** for all VM definitions |
| `infrastructure/` | OpenTofu IaC (VM provisioning) |
| `infrastructure/templates/` | Cloud-init templates (reference only, not deployed) |
| `nixos/` | NixOS + Colmena configuration |
| `nixos/hosts/` | Per-host NixOS configurations |
| `nixos/modules/` | Reusable NixOS modules |
| `nixos/stacks/` | Docker Compose stacks (deployed via Colmena) |
| `scripts/` | Deployment automation scripts |

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

3. Register in `nixos/flake.nix` colmenaHive

4. Create stack at `nixos/stacks/newvm/compose.yml`

5. Create 1Password secret: `op item create --category="Secure Note" --title="env-newvm-stack" --vault="Infrastructure" 'notesPlain=KEY=value'`

6. Deploy: `tofu apply && colmena apply --on newvm`

## Secrets Management

- Colmena `deployment.keys` with `keyCommand` using `op read`
- Never commit `.env` files - use `.env.example` templates
- Reference format: `op://Infrastructure/env-<stack>-stack/notesPlain`

## Key Architecture Patterns

- **Single source of truth**: All VM config (IP, MAC, resources) defined in `nixos/hosts.json`
- **Traefik per VM**: Each stack runs its own Traefik for subdomain routing
- **NFS backup**: Configs at `/opt/stacks/<stack>/config/` synced hourly to NFS
- **Docker TCP**: Enable on VMs needing remote discovery (Homepage)
- **GPU VMs**: Require `gpu: true` and `gpuId` in hosts.json

## Common Gotchas

- Cloud-init only runs on first boot; recreate VM for config changes
- NVIDIA GPU passthrough requires `rombar = false`
- After IP reuse, clear SSH known_hosts: `ssh-keygen -R <ip>`
- New files in nixos/ must be `git add`ed before `colmena build` (Nix flakes only see tracked files)
