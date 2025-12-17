# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Infrastructure-as-code for deploying Docker hosts on Proxmox using a hybrid **OpenTofu + NixOS + Colmena** architecture:

- **OpenTofu**: Provisions VMs on Proxmox (clones NixOS template or boots Ubuntu cloud image)
- **NixOS + Colmena**: Manages NixOS VM configuration (Docker, compose stacks, backups)
- **1Password**: Secrets management via `op` CLI

## Architecture

```
homelab/
├── infrastructure/          # OpenTofu IaC (VM provisioning)
│   ├── main.tf              # VM definitions (NixOS clones + Ubuntu cloud-init)
│   ├── secrets.tf           # 1Password data sources
│   └── templates/           # Cloud-init templates (Ubuntu only)
│
├── nixos/                   # NixOS + Colmena (configuration management)
│   ├── flake.nix            # Main flake: image build + Colmena hive
│   ├── image.nix            # Base NixOS image for Proxmox
│   ├── hosts/               # Per-host configurations
│   │   ├── arr.nix          # Media automation VM
│   │   └── tools.nix        # Utility tools VM
│   └── modules/             # Reusable NixOS modules
│       ├── base.nix         # Common config (SSH, users, packages)
│       ├── docker-stack.nix # Docker + compose systemd service
│       ├── nfs-backup.nix   # NFS backup/restore services
│       └── homepage.nix     # Homepage dashboard config
│
├── stacks/                  # Docker Compose stacks
│   ├── arr/                 # Media automation (Sonarr, Radarr, etc.)
│   ├── tools/               # Utility tools (Homepage, Stirling PDF)
│   └── portainer/           # Ubuntu reference VM stack
│
└── scripts/                 # Automation scripts
    ├── deploy.sh            # Full deployment script
    └── upload-nixos-image.sh # Build and upload NixOS image to Proxmox
```

## VM Overview

| VM | OS | IP | Purpose | Management |
|----|----|----|---------|------------|
| arr | NixOS | 10.0.0.20 | Media automation (arr stack) | Colmena |
| tools | NixOS | 10.0.0.21 | Utility tools | Colmena |
| portainer | Ubuntu | 10.0.0.22 | Reference VM (cloud-init) | OpenTofu |

## Common Commands

```bash
# Enter development environment (loads tools + 1Password secrets)
direnv allow

# ============================================================
# Full Deployment
# ============================================================
./scripts/deploy.sh                    # Build image + provision VMs + deploy configs

# ============================================================
# NixOS Image Management
# ============================================================
cd nixos && nix build .#proxmox-image  # Build NixOS Proxmox image
./scripts/upload-nixos-image.sh        # Upload image to Proxmox as template

# ============================================================
# OpenTofu (VM Provisioning)
# ============================================================
cd infrastructure
tofu init
tofu plan
tofu apply

# ============================================================
# Colmena (NixOS Configuration)
# ============================================================
cd nixos
colmena build                          # Build without deploying
colmena apply                          # Deploy to all NixOS hosts
colmena apply --on arr                 # Deploy to specific host
colmena apply --on @media              # Deploy to hosts by tag
colmena upload-keys                    # Update secrets only

# ============================================================
# Recreate a VM
# ============================================================
# Ubuntu VM (full rebuild):
tofu apply -replace='proxmox_virtual_environment_vm.ubuntu_vm["portainer"]'

# NixOS VM (usually just use colmena, but if needed):
tofu apply -replace='proxmox_virtual_environment_vm.nixos_vm["arr"]'
```

## Deployment Workflow

### Initial Setup (First Time)

```bash
# 1. Build and upload NixOS image to Proxmox
cd nixos && nix build .#proxmox-image
./scripts/upload-nixos-image.sh

# 2. Provision VMs
cd infrastructure && tofu apply

# 3. Deploy NixOS configurations
cd nixos && colmena apply
```

### Day-to-Day Changes

```bash
# Change to NixOS config (modules, hosts, compose files):
cd nixos && colmena apply

# Change to VM specs (CPU, memory, new VM):
cd infrastructure && tofu apply

# Change to NixOS base image:
cd nixos && nix build .#proxmox-image
./scripts/upload-nixos-image.sh
# Existing VMs don't need rebuild - colmena handles config updates
```

## Adding a New NixOS VM

1. **Add host config** in `nixos/hosts/newvm.nix`:
   ```nix
   { config, pkgs, lib, stacksPath, ... }:
   {
     networking.hostName = "newvm";
     networking.interfaces.ens18.ipv4.addresses = [{
       address = "10.0.0.XX";
       prefixLength = 24;
     }];
     # ... rest of config
   }
   ```

2. **Add to Colmena hive** in `nixos/flake.nix`:
   ```nix
   colmenaHive = colmena.lib.makeHive {
     # ...
     newvm = import ./hosts/newvm.nix;
   };
   ```

3. **Add VM to OpenTofu** in `infrastructure/main.tf`:
   ```hcl
   nixos_vms = {
     newvm = {
       node = "strongmad", vm_id = 203, ip = "10.0.0.XX/24",
       mac_address = "BC:24:11:00:00:XX",
       cores = 2, memory = 2048, disk_gb = 30,
       domain = "newvm.tap"
     }
   }
   ```

4. **Create compose stack** in `stacks/newvm/compose.yml`

5. **Create 1Password secret**:
   ```bash
   op item create --category="Secure Note" --title="env-newvm-stack" \
     --vault="Infrastructure" 'notesPlain=KEY=value'
   ```

6. **Deploy**:
   ```bash
   cd infrastructure && tofu apply
   cd nixos && colmena apply --on newvm
   ```

## Secret Management

### NixOS VMs (Colmena)
Secrets are deployed via Colmena's `deployment.keys` using 1Password CLI:
```nix
deployment.keys."stack-env" = {
  keyCommand = [ "op" "read" "op://Infrastructure/env-arr-stack/notesPlain" ];
  destDir = "/opt/stacks/arr";
  name = ".env";
};
```

### Ubuntu VMs (Cloud-init)
Secrets are fetched at `tofu apply` time and embedded in cloud-init.

### Creating a New Secret
```bash
op item create --category="Secure Note" --title="env-STACKNAME-stack" \
  --vault="Infrastructure" 'notesPlain=KEY1=value1
KEY2=value2'
```

## Key Patterns

- **Traefik routing**: Each stack runs Traefik for subdomain routing (e.g., `sonarr.arr.tap`)
- **NFS backup**: Configs at `/opt/stacks/<stack>/config/` synced hourly to NFS
- **Docker TCP**: arr VM exposes Docker socket on port 2375 for Homepage discovery
- **Homepage config**: Managed declaratively in `nixos/modules/homepage.nix`

## Cloud-Init Gotchas (Ubuntu VMs only)

- Cloud-init only runs on first boot; recreate VM for config changes
- Provider's `user_account` conflicts with `user_data_file_id` - use one or the other
- Ubuntu 24.04 requires SeaBIOS + IDE (not EFI) for cloud-init
- Use `${replace(content, "\n", "\n      ")}` for proper YAML indentation

## Troubleshooting

### Colmena can't connect to host
```bash
# Check SSH access
ssh root@10.0.0.20

# Verify host is in known_hosts
ssh-keygen -R 10.0.0.20  # Remove old key if IP reused
```

### NixOS image upload fails
```bash
# Check Proxmox SSH access
ssh root@<proxmox-host>

# Verify storage has space
pvesm status
```

### Stack not starting
```bash
# SSH to host and check systemd service
ssh root@10.0.0.20
systemctl status arr-stack.service
journalctl -u arr-stack.service
```
