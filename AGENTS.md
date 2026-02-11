# AGENTS.md

Instructions for AI coding agents working in this repository.

## Project Overview

Infrastructure-as-code for deploying NixOS Docker hosts on Proxmox using:
- **OpenTofu**: VM provisioning (downloads Debian cloud image, creates VMs)
- **pfSense**: DNS and DHCP management via OpenTofu (marshallford/pfsense provider)
- **nixos-anywhere**: Installs NixOS over SSH onto Debian VMs (uses disko for partitioning)
- **NixOS + Colmena**: Configuration management for all VMs
- **1Password**: Secrets management via `op` CLI
- **Justfile**: Task orchestration (replaces deploy scripts)

## Build/Deploy Commands

```bash
# Enter development environment (required - loads tools + 1Password secrets)
direnv allow

# List all available commands
just

# Generate artifacts from Nix definitions
just generate                          # Generate artifacts/hosts.json from nixos/flake.nix

# OpenTofu (VM provisioning)
just init                              # Initialize providers
just plan                              # Preview changes
just tofu                              # Apply all changes

# nixos-anywhere (provision NixOS on a Debian VM - WIPES DISK!)
just provision <host>                  # Provision single host
just provision-all                     # Provision all hosts

# Secrets
just secrets                           # Generate secrets.auto.tfvars from 1Password

# Colmena (NixOS configuration)
just deploy                            # Deploy to all hosts (with GPU fix)
just deploy-on <host>                  # Deploy to specific host
just upload-keys                       # Update secrets only

# Utility
just info                              # Show host IPs and domains
just validate                          # Check artifacts/hosts.json is valid

# Manual OpenTofu commands (run from infrastructure/)
tofu apply -target='proxmox_virtual_environment_vm.nixos_vm["arr"]'  # Single VM
tofu apply -replace='proxmox_virtual_environment_vm.nixos_vm["arr"]' # Recreate VM

# Manual Colmena commands (run from nixos/)
colmena build                          # Build without deploying
colmena apply --on @media              # Deploy by tag

# Build NixOS config for a host (verify it compiles)
nix build ./nixos#nixosConfigurations.tools.config.system.build.toplevel
```

## Testing & Validation

No automated test suite exists. Validation is done via:
```bash
just plan                              # Check OpenTofu changes
just validate                          # Validate generated JSON
colmena build                          # Verify NixOS configs compile (run from nixos/)
nix flake check                        # Check flake validity (run from nixos/)
nix eval --json .#terraformHosts       # Verify terraform output (run from nixos/)
```

## Code Style Guidelines

### Justfile
- Use `set shell := ["bash", "-euo", "pipefail", "-c"]` for strict mode
- Color-coded output matching the log_info/log_warn/log_error/log_step pattern
- Use shebang recipes (`#!/usr/bin/env bash`) for multi-line bash logic
- Use `@` prefix for quiet commands (e.g., echo statements)
- Define directory variables at the top with `justfile_directory()`

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
| `nixos/flake.nix` | **Single source of truth** for all VM definitions (hosts attrset) |
| `nixos/lib/` | Host wiring, validation, and flake output generation |
| `nixos/lib/hosts.nix` | Entry point: shared modules, validation, delegates to outputs |
| `nixos/lib/hosts/modules.nix` | Host validation + NixOS module assembly |
| `nixos/lib/hosts/outputs.nix` | Generates nixosConfigurations, colmenaHive, terraformHosts |
| `nixos/hosts/` | Per-host NixOS configurations |
| `nixos/modules/` | Reusable NixOS modules (base, disko, docker-stack, etc.) |
| `nixos/stacks/` | Docker Compose stacks (deployed via Colmena) |
| `artifacts/` | Generated files (hosts.json for OpenTofu, created by `just generate`) |
| `infrastructure/` | OpenTofu IaC (VM provisioning, reads `artifacts/hosts.json`) |
| `Justfile` | Task orchestration (replaces deploy.sh) |

## Data Flow

```
nixos/flake.nix (hosts defined as Nix attrset)
  |
  +-> nixos/lib/hosts.nix (validates, wires shared modules)
  |     +-> nixos/lib/hosts/modules.nix (validateHost, mkHostConfig)
  |     +-> nixos/lib/hosts/outputs.nix (nixosConfigurations, colmenaHive, terraformHosts)
  |
  +-> `just generate` runs `nix eval --json .#terraformHosts > artifacts/hosts.json`
  +-> `just tofu` runs OpenTofu which reads artifacts/hosts.json
  +-> `just provision <host>` runs nixos-anywhere
  +-> `just deploy` runs colmena apply + GPU fix
```

## Naming Conventions

- **VM names**: lowercase, short (arr, tools, nvr, aria)
- **Stack names**: match VM names
- **NixOS hosts**: `nixos/hosts/<vmname>.nix`
- **1Password secrets**: `env-<stackname>-stack` in Infrastructure vault
- **IP addresses**: 10.0.0.XX/24 (see hosts attrset in `nixos/flake.nix`)
- **MAC addresses**: `BC:24:11:00:00:XX` prefix

## Adding a New NixOS VM

1. Add VM to the `hosts` attrset in `nixos/flake.nix`:
   ```nix
   newvm = {
     ip = "10.0.0.XX";
     mac = "BC:24:11:00:00:XX";
     node = "strongmad";
     vmId = 206;
     cores = 2;
     memory = 2048;
     disk = 30;
     domain = "newvm.tap";
     tags = [ "docker" "nixos" ];
     gpu = false;
   };
   ```
   For GPU VMs, set `gpu = true` and add `gpuId`:
   ```nix
   newgpuvm = {
     # ...same fields...
     gpu = true;
     gpuId = "0000:01:00";  # PCI device ID from Proxmox
   };
   ```

2. Create host config at `nixos/hosts/newvm.nix`

3. Create stack at `nixos/stacks/newvm/compose.yml`

4. Create 1Password secret: `op item create --category="Secure Note" --title="env-newvm-stack" --vault="Infrastructure" 'notesPlain=KEY=value'`

5. Deploy:
   ```bash
   just generate                          # Regenerate artifacts/hosts.json
   just tofu                              # Provision VM (Debian)
   just provision newvm                   # Install NixOS via nixos-anywhere
   just deploy                            # Deploy config via Colmena
   ```

## Secrets Management

- Colmena `deployment.keys` with `keyCommand` using `op read`
- Never commit `.env` files - use `.env.example` templates
- Reference format: `op://Infrastructure/env-<stack>-stack/notesPlain`

## Key Architecture Patterns

- **Single source of truth**: All VM config (IP, MAC, resources) defined as Nix attrset in `nixos/flake.nix`
- **Generated artifacts**: `just generate` produces `artifacts/hosts.json` from Nix definitions for OpenTofu
- **Debian cloud image + nixos-anywhere**: OpenTofu downloads the Debian cloud image and creates VMs (cloud-init for SSH+IP), then nixos-anywhere installs NixOS over SSH
- **Disko**: Declarative disk partitioning (GPT + BIOS boot + ext4 root) shared across all VMs
- **Shared NixOS modules**: `sharedModules` in `nixos/lib/hosts.nix` used by both `nixosConfigurations` and `colmenaHive`
- **Host wiring**: `nixos/lib/hosts/modules.nix` validates hosts and assembles per-host module lists
- **Traefik per VM**: Each stack runs its own Traefik for subdomain routing
- **NFS backup**: Configs at `/opt/stacks/<stack>/config/` synced hourly to NFS
- **Docker TCP**: Enable on VMs needing remote discovery (Homepage)
- **Unified VM resource**: All VMs (GPU and non-GPU) use a single `proxmox_virtual_environment_vm.nixos_vm` resource with conditionals for `machine`, `vga.memory`, `tags`, and `dynamic "hostpci"`
- **GPU VMs**: Require `gpu = true` and `gpuId` in hosts attrset; the unified resource automatically sets q35 machine type, minimal VGA memory, and PCI passthrough

## Common Gotchas

- Cloud-init only runs on first boot; recreate VM (`tofu apply -replace=...`) for cloud-init config changes
- nixos-anywhere wipes disks — use with caution on existing VMs
- After nixos-anywhere, host SSH keys change — `ssh-keygen -R <ip>` (Justfile does this automatically)
- NVIDIA GPU passthrough requires `rombar = false`
- After IP reuse, clear SSH known_hosts: `ssh-keygen -R <ip>`
- New files in nixos/ must be `git add`ed before `colmena build` (Nix flakes only see tracked files)
- `networking.usePredictableInterfaceNames = false` is in `base.nix` — required for `eth0` references
- Run `just generate` after changing host definitions before running `just tofu` or `just plan`

## Stack-Specific Configuration

### Mem Stack (aria)
The mem video processing stack requires special configuration for RTMP streaming:
- Set `RTMP_HOST` environment variable to the external hostname (e.g., `aria.tap`)
- Configure `streaming.rtmp.host` in `config/mem/config.yaml`
- This ensures OBS receives correct RTMP URLs for connecting from outside Docker network
- Uses `pull_policy: always` to auto-update images when containers restart
