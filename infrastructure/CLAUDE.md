# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Overview

OpenTofu infrastructure for provisioning VMs on Proxmox VE. This directory handles VM creation and sizing; NixOS configuration is managed by Colmena in `../nixos/`.

## Commands

```bash
# Enter dev environment (loads 1Password secrets via direnv)
cd /home/sdelcore/src/homelab && direnv allow

# Standard workflow
tofu init                    # Initialize providers
tofu plan                    # Preview changes
tofu apply                   # Apply all changes

# Target specific VM
tofu apply -target='proxmox_virtual_environment_vm.nixos_vm["aria"]'

# Recreate VM (destructive)
tofu apply -replace='proxmox_virtual_environment_vm.nixos_vm["arr"]'

# After provisioning NixOS VMs, deploy config:
cd ../nixos && colmena apply --on aria
```

## Architecture

Three VM types defined in `main.tf`:

| Type | Location | Provisioning |
|------|----------|--------------|
| `nixos_vms` | `locals.nixos_vms` | Cloned from template, configured by Colmena |
| `nixos_gpu_vms` | `locals.nixos_gpu_vms` | q35 machine + PCI passthrough |
| `ubuntu_vms` | `locals.ubuntu_vms` | Cloud-init at first boot |

## Current VMs

| Name | Type | VM ID | IP | Node |
|------|------|-------|-----|------|
| arr | NixOS | 200 | 10.0.0.20 | strongmad |
| tools | NixOS | 201 | 10.0.0.21 | strongmad |
| portainer | Ubuntu | 202 | 10.0.0.22 | strongmad |
| nvr | NixOS+GPU | 203 | 10.0.0.16 | strongbad |
| aria | NixOS | 204 | 10.0.0.23 | strongmad |

## Adding a New NixOS VM

1. Add to `locals.nixos_vms` in `main.tf`:
   ```hcl
   newvm = {
     node        = "strongmad"
     vm_id       = 205
     ip          = "10.0.0.XX/24"
     mac_address = "BC:24:11:00:00:XX"
     cores       = 2
     memory      = 2048
     disk_gb     = 30
     domain      = "newvm.tap"
   }
   ```

2. Run `tofu apply`

3. Add host config in `../nixos/hosts/newvm.nix` and register in `../nixos/flake.nix`

4. Deploy: `cd ../nixos && colmena apply --on newvm`

## Secrets

Environment loaded via `../.envrc` (direnv):
- Proxmox API credentials: `TF_VAR_proxmox_api_url`, `TF_VAR_proxmox_api_token_id`, `TF_VAR_proxmox_api_token_secret`
- 1Password service account: `OP_SERVICE_ACCOUNT_TOKEN`
- Stack secrets fetched via 1Password provider in `secrets.tf`

## Key Files

| File | Purpose |
|------|---------|
| `main.tf` | VM definitions (all three types) |
| `providers.tf` | Proxmox + 1Password provider config |
| `secrets.tf` | Fetches stack .env from 1Password |
| `outputs.tf` | VM IPs, Colmena hosts, DNS config |
| `templates/ubuntu-cloud-init.yaml.tpl` | Full cloud-init for Ubuntu VMs |

## GPU VM Notes

GPU VMs (`nixos_gpu_vms`) require:
- `machine = "q35"` for PCIe passthrough
- `hostpci` block with GPU PCI address
- `rombar = false` for NVIDIA cards
- Local storage (not NFS) for reliability

## Cloud-Init Gotchas

See detailed troubleshooting in `README.md`. Key points:
- Cloud-init only runs on first boot; recreate VM for config changes
- Use `replace()` not `indent()` for YAML multiline content
- Ubuntu 24.04 requires SeaBIOS (not EFI) for cloud-init
