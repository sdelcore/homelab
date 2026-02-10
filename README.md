# Homelab

Infrastructure-as-code for deploying Docker hosts on Proxmox using OpenTofu, NixOS, and Colmena.

## Overview

This repository uses a hybrid infrastructure approach:

- **OpenTofu**: Provisions VMs on Proxmox (clones NixOS templates or boots Ubuntu cloud images)
- **NixOS + Colmena**: Manages NixOS VM configuration (Docker, compose stacks, backups)
- **1Password**: Secrets management via `op` CLI

## Architecture

```
homelab/
├── infrastructure/          # OpenTofu IaC (VM provisioning)
│   ├── main.tf              # VM definitions
│   ├── secrets.tf           # 1Password data sources
│   └── templates/           # Cloud-init templates (Ubuntu only)
│
├── nixos/                   # NixOS + Colmena (configuration management)
│   ├── flake.nix            # Main flake: image build + Colmena hive
│   ├── image.nix            # Base NixOS image for Proxmox
│   ├── hosts/               # Per-host configurations (arr.nix, tools.nix, etc.)
│   ├── modules/             # Reusable NixOS modules
│   └── stacks/              # Docker Compose stacks (deployed via Colmena)
│
├── scripts/                 # Automation scripts
│   ├── deploy.sh            # Full deployment script
│   └── upload-nixos-image.sh
│
└── docs/                    # Additional documentation
    └── cloud-init.md        # Cloud-init troubleshooting
```

### VM Overview

| VM | Type | VM ID | IP | Node | Purpose |
|----|------|-------|-----|------|---------|
| arr | NixOS | 200 | 10.0.0.20 | strongmad | Media automation |
| tools | NixOS | 201 | 10.0.0.21 | strongmad | Utility tools |
| portainer | Ubuntu | 202 | 10.0.0.22 | strongmad | Reference VM |
| nvr | NixOS+GPU | 203 | 10.0.0.16 | strongbad | Surveillance |
| aria | NixOS | 204 | 10.0.0.23 | strongmad | App server |

## Prerequisites

- **Nix** with flakes enabled
- **direnv** for automatic environment loading
- **1Password CLI** (`op`) configured and authenticated
- **SSH key pair** for VM access
- **Proxmox VE** >= 8.0 with API access

## Quick Start

```bash
# 1. Allow direnv (loads tools + 1Password secrets)
direnv allow

# 2. Build and upload NixOS image to Proxmox
cd nixos && nix build .#proxmox-image
./scripts/upload-nixos-image.sh

# 3. Provision VMs
cd infrastructure && tofu init && tofu apply

# 4. Deploy NixOS configurations
cd nixos && colmena apply
```

Or use the full deployment script:

```bash
./scripts/deploy.sh                    # Full: image + tofu + colmena
./scripts/deploy.sh --colmena-only     # NixOS configs only
./scripts/deploy.sh --tofu-only        # VM provisioning only
./scripts/deploy.sh --image-only       # NixOS image build/upload only
```

## Deployment Workflows

### Day-to-Day Changes

```bash
# NixOS config changes (modules, hosts, compose files):
cd nixos && colmena apply

# VM spec changes (CPU, memory, new VM):
cd infrastructure && tofu apply

# Update secrets only:
cd nixos && colmena upload-keys
```

### Targeting Specific Hosts

```bash
colmena apply --on arr           # Single host
colmena apply --on @media        # By tag
tofu apply -target='proxmox_virtual_environment_vm.nixos_vm["arr"]'
```

### Recreating a VM

```bash
# NixOS VM:
tofu apply -replace='proxmox_virtual_environment_vm.nixos_vm["arr"]'
colmena apply --on arr

# Ubuntu VM:
tofu apply -replace='proxmox_virtual_environment_vm.ubuntu_vm["portainer"]'
```

## Adding a New NixOS VM

1. **Add VM to OpenTofu** in `infrastructure/main.tf`:
   ```hcl
   nixos_vms = {
     newvm = {
       node = "strongmad", vm_id = 205, ip = "10.0.0.XX/24",
       mac_address = "BC:24:11:00:00:XX",
       cores = 2, memory = 2048, disk_gb = 30, domain = "newvm.tap"
     }
   }
   ```

2. **Create host config** at `nixos/hosts/newvm.nix`

3. **Register in Colmena** in `nixos/flake.nix`:
   ```nix
   colmenaHive = colmena.lib.makeHive {
     # ...
     newvm = import ./hosts/newvm.nix;
   };
   ```

4. **Create compose stack** at `nixos/stacks/newvm/compose.yml`

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

## Docker Stacks

Each NixOS VM runs a Docker Compose stack located in `nixos/stacks/<vmname>/`:

| Stack | VM | Description |
|-------|-----|-------------|
| arr | arr | Media automation (Sonarr, Radarr, Deluge, etc.) |
| tools | tools | Infrastructure tools (Homepage, Stirling PDF) |
| aria | aria | Aria2 download manager |
| nvr | nvr | Frigate NVR with GPU passthrough |

Stacks are deployed via the `dockerStack` NixOS module and managed as systemd services.

## Secrets Management

### 1Password Setup

Create these items in your "Infrastructure" vault:

1. **Proxmox** - Login item with `url`, `token_id`, `credential`
2. **env-{stack}-stack** - Secure Note containing `.env` content for each stack
3. **sdelcore** - User credentials with `password` field (hashed)

### How Secrets Work

**NixOS VMs**: Colmena fetches secrets at deploy time using `op read`:
```nix
deployment.keys."stack-env" = {
  keyCommand = [ "op" "read" "op://Infrastructure/env-arr-stack/notesPlain" ];
  destDir = "/opt/stacks/arr";
  name = ".env";
};
```

**Ubuntu VMs**: Secrets are fetched at `tofu apply` time and embedded in cloud-init.

### Creating a New Secret

```bash
op item create --category="Secure Note" --title="env-STACKNAME-stack" \
  --vault="Infrastructure" 'notesPlain=KEY1=value1
KEY2=value2'
```

## Troubleshooting

### Colmena Can't Connect to Host

```bash
# Check SSH access
ssh root@10.0.0.20

# Clear old SSH key if IP was reused
ssh-keygen -R 10.0.0.20
```

### NixOS Image Upload Fails

```bash
# Check Proxmox SSH access
ssh root@<proxmox-host>

# Verify storage has space
pvesm status
```

### Stack Not Starting

```bash
ssh root@10.0.0.20
systemctl status arr-stack.service
journalctl -u arr-stack.service
```

### GPU Passthrough Issues

GPU VMs require:
- `machine = "q35"` for PCIe passthrough
- `rombar = false` for NVIDIA cards
- Local storage (not NFS) for reliability

### Cloud-Init Issues (Ubuntu VMs)

See [docs/cloud-init.md](docs/cloud-init.md) for detailed troubleshooting.

Key points:
- Cloud-init only runs on first boot; recreate VM for config changes
- Ubuntu 24.04 requires SeaBIOS (not EFI)
- Use `replace()` not `indent()` for YAML multiline content

## References

- [Proxmox Cloud-Init Support](https://pve.proxmox.com/wiki/Cloud-Init_Support)
- [Colmena Manual](https://colmena.cli.rs/unstable/)
- [NixOS Manual](https://nixos.org/manual/nixos/stable/)
- [bpg/proxmox Terraform Provider](https://registry.terraform.io/providers/bpg/proxmox/latest/docs)
