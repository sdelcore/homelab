# Homelab

Infrastructure-as-code for deploying NixOS Docker hosts on Proxmox using OpenTofu, nixos-anywhere, and Colmena.

## Overview

- **OpenTofu**: Provisions VMs on Proxmox (downloads Debian cloud image, creates VMs with cloud-init)
- **pfSense**: DNS and DHCP management via OpenTofu (marshallford/pfsense provider)
- **nixos-anywhere**: Installs NixOS over SSH onto provisioned Debian VMs (uses disko for disk partitioning)
- **NixOS + Colmena**: Configuration management and secrets deployment for all VMs
- **1Password**: Secrets management via `op` CLI
- **Justfile**: Task orchestration

All VM definitions live in a single Nix attrset in `nixos/flake.nix`. Running `just generate` produces `artifacts/hosts.json` which OpenTofu reads to provision VMs.

## VM Overview

| VM | VM ID | IP | Node | Purpose |
|----|-------|-----|------|---------|
| arr | 200 | 10.0.0.20 | strongmad | Media automation |
| tools | 201 | 10.0.0.21 | strongmad | Utility tools |
| nvr | 203 | 10.0.0.16 | strongbad | Surveillance (GPU) |
| aria | 204 | 10.0.0.23 | strongmad | App server |
| media | 205 | 10.0.0.15 | strongbad | Media services (GPU) |

## Prerequisites

These one-time manual steps are required before OpenTofu can manage the full stack:

### pfSense DNS Resolver

The DNS config file is pushed to pfSense automatically, but Unbound must be configured to include it:

1. Navigate to **Services → DNS Resolver → General Settings**
2. Add to **Custom Options**: `include-toplevel: /var/unbound/conf.d/*`
3. Save and apply

### pfSense DHCP

DHCP static mappings are managed by OpenTofu automatically. No manual pfSense configuration is needed — `just tofu` creates and applies all MAC → IP mappings.

### Proxmox GPU Passthrough

For GPU VMs (`gpu = true`), create a PCI resource mapping in Proxmox before applying:

1. Navigate to **Datacenter → Resource Mappings → PCI Devices**
2. Add the GPU device (note the PCI ID, e.g., `0000:01:00`)
3. Use that PCI ID as `gpuId` in the host definition

### 1Password

A service account token must exist at `~/.config/op/service-account-token`. This is loaded automatically by `.envrc`.

## Quick Start

```bash
# 1. Allow direnv (loads tools + 1Password secrets)
direnv allow

# 2. Generate secrets and initialize providers (first time only)
just secrets
just init

# 3. Day-to-day deployment
just generate                          # Regenerate artifacts from Nix
just tofu                              # Apply VM + DNS/DHCP changes
just deploy                            # Deploy NixOS configs via Colmena
```

## Deployment Workflows

### Day-to-Day Changes

```bash
just deploy                            # Deploy NixOS configs to all hosts
just deploy-on arr                     # Deploy to a specific host
just upload-keys                       # Update secrets only
just tofu                              # Apply VM spec changes
```

### Provisioning a New or Recreated VM

```bash
just generate                          # Regenerate artifacts/hosts.json from Nix
just tofu                              # Provision VM (Debian cloud image)
just provision <host>                  # Install NixOS via nixos-anywhere (WIPES DISK)
just deploy                            # Deploy config via Colmena
```

### Targeting Specific Hosts

```bash
# OpenTofu (all VMs, including GPU, use nixos_vm)
tofu apply -target='proxmox_virtual_environment_vm.nixos_vm["arr"]'
tofu apply -replace='proxmox_virtual_environment_vm.nixos_vm["arr"]'  # Recreate

# Colmena
colmena apply --on arr                 # Single host
colmena apply --on @media              # By tag
```

## Docker Stacks

Each NixOS VM runs a Docker Compose stack located in `nixos/stacks/<vmname>/`:

| Stack | VM | Description |
|-------|-----|-------------|
| arr | arr | Media automation (Sonarr, Radarr, Deluge, etc.) |
| tools | tools | Infrastructure tools (Homepage, Stirling PDF) |
| aria | aria | Aria2 + mem video processing |
| nvr | nvr | Frigate NVR with GPU passthrough |
| media | media | Media services with GPU passthrough |

Stacks are deployed via the `dockerStack` NixOS module and managed as systemd services.

## Secrets Management

Secrets are stored in 1Password and fetched at deploy time by Colmena:

```nix
deployment.keys."stack-env" = {
  keyCommand = [ "op" "read" "op://Infrastructure/env-arr-stack/notesPlain" ];
  destDir = "/opt/stacks/arr";
  name = ".env";
};
```

Create a new secret:
```bash
op item create --category="Secure Note" --title="env-STACKNAME-stack" \
  --vault="Infrastructure" 'notesPlain=KEY1=value1
KEY2=value2'
```

## Troubleshooting

### Colmena Can't Connect to Host

```bash
ssh root@<ip>                          # Check SSH access
ssh-keygen -R <ip>                     # Clear stale host key
```

### Stack Not Starting

```bash
ssh root@<ip>
systemctl status <stack>-stack.service
journalctl -u <stack>-stack.service
```

### GPU Passthrough Issues

GPU VMs use a unified resource (`proxmox_virtual_environment_vm.nixos_vm`) that automatically configures:
- `machine = "q35"` for PCIe passthrough
- `rombar = false` for NVIDIA cards
- Minimal VGA memory (16MB) for console access

Set `gpu = true` and `gpuId` in the host definition — no separate resource needed. Ensure the PCI resource mapping exists in Proxmox UI before applying.

## References

- [Colmena Manual](https://colmena.cli.rs/unstable/)
- [NixOS Manual](https://nixos.org/manual/nixos/stable/)
- [bpg/proxmox Terraform Provider](https://registry.terraform.io/providers/bpg/proxmox/latest/docs)
- [marshallford/pfsense Terraform Provider](https://registry.terraform.io/providers/marshallford/pfsense/latest/docs)
- [nixos-anywhere](https://github.com/nix-community/nixos-anywhere)
- [disko](https://github.com/nix-community/disko)
