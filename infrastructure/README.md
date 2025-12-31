# Homelab Infrastructure

OpenTofu/Terraform infrastructure for provisioning VMs on Proxmox VE with cloud-init configuration, 1Password secrets integration, and automated Docker stack deployment.

## Overview

This infrastructure manages:

- **Ubuntu VMs** - Docker hosts with cloud-init for automated setup
- **NixOS VMs** - Deployed via nixos-anywhere (Ubuntu bootstrap → NixOS conversion)
- **Secrets** - Pulled from 1Password at apply time
- **Backups** - NFS-based config backup/restore

### Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                     OpenTofu/Terraform                       │
├─────────────────────────────────────────────────────────────┤
│  main.tf          │ VM definitions, cloud-init resources    │
│  secrets.tf       │ 1Password integration                   │
│  providers.tf     │ Proxmox + 1Password providers           │
│  variables.tf     │ Configurable parameters                 │
├─────────────────────────────────────────────────────────────┤
│                      Templates                               │
├─────────────────────────────────────────────────────────────┤
│  ubuntu-cloud-init.yaml.tpl  │ Full cloud-init config       │
│  nixos-bootstrap.yaml.tpl    │ Minimal SSH-only bootstrap   │
│  scripts/*.sh.tpl            │ Docker, backup, restore      │
└─────────────────────────────────────────────────────────────┘
           │
           ▼
┌─────────────────────────────────────────────────────────────┐
│                      Proxmox VE                              │
├─────────────────────────────────────────────────────────────┤
│  VM 200: arr       │ NixOS + Docker (media stack)           │
│  VM 201: tools     │ NixOS + Docker (utility tools)         │
│  VM 202: portainer │ Ubuntu + Docker (reference VM)         │
│  VM 203: nvr       │ NixOS + Docker + GPU (surveillance)    │
│  VM 204: aria      │ NixOS + Docker (app server)            │
└─────────────────────────────────────────────────────────────┘
```

## Prerequisites

- **OpenTofu** (or Terraform) >= 1.6
- **Proxmox VE** >= 8.0 with API access
- **1Password CLI** (`op`) configured and authenticated
- **SSH key pair** at `~/.ssh/id_rsa` (or configure path)
- **direnv** for automatic environment loading
- **Nix** with flakes (for NixOS VMs and home-manager)

### Proxmox Requirements

- API token with VM and storage permissions
- `local` storage configured for snippets
- `local-lvm` (or similar) for VM disks
- Ubuntu cloud image downloaded or URL accessible

## Quick Start

```bash
# 1. Clone and enter directory
cd infrastructure

# 2. Create terraform.tfvars
cat > terraform.tfvars << 'EOF'
ssh_public_keys = [
  "ssh-rsa AAAA... your-key-here"
]
EOF

# 3. Allow direnv (loads 1Password secrets)
direnv allow

# 4. Initialize and apply
tofu init
tofu apply
```

## Configuration

### Variables (terraform.tfvars)

| Variable | Description | Default |
|----------|-------------|---------|
| `ssh_public_keys` | List of SSH public keys for VM access | Required |
| `vm_user` | Default username for VMs | `sdelcore` |
| `proxmox_node` | Proxmox node name | `pve` |
| `vm_storage` | Storage for VM disks | `local-lvm` |
| `snippet_storage` | Storage for cloud-init snippets | `local` |
| `vm_bridge` | Network bridge | `vmbr0` |
| `enable_nixos_vms` | Enable NixOS VM deployment | `false` |
| `enable_home_manager` | Install home-manager on Ubuntu VMs | `true` |

### Adding a New VM

1. Add entry to `locals.ubuntu_vms` in `main.tf`:
   ```hcl
   new_vm = {
     node    = "proxmox-node"
     vm_id   = 203
     ip      = "10.0.0.20/24"
     cores   = 2
     memory  = 2048
     disk_gb = 30
     stack   = "your-stack"
   }
   ```

2. Create stack compose file at `../stacks/your-stack/compose.yml`

3. Add stack secrets to 1Password (item named `your-stack Environment`)

4. Run `tofu apply`

## Cloud-Init Troubleshooting

This section documents critical lessons learned debugging cloud-init issues.

### Issue 1: Provider Conflict

**Problem:** SSH keys not being applied to VMs.

**Cause:** The bpg/proxmox provider's `user_account` block **conflicts** with `user_data_file_id`. You cannot use both simultaneously.

**Solution:** Choose one approach:
- Use `user_data_file_id` with full cloud-init template (recommended for complex setups)
- Use `user_account` only for simple username/password/keys

### Issue 2: YAML Indentation in Templates

**Problem:** Cloud-init fails with YAML parsing errors like:
```
Failed loading yaml blob. Invalid format at line 52: PUID=1000
```

**Cause:** Terraform's `indent()` function does NOT indent the first line of content. In YAML literal blocks (`content: |`), all lines must be consistently indented.

**Broken:**
```hcl
content: |
${indent(6, my_content)}
```
Produces:
```yaml
content: |
first line here    # No indentation!
      second line  # Indented
```

**Working:**
```hcl
content: |
      ${replace(my_content, "\n", "\n      ")}
```
Produces:
```yaml
content: |
      first line   # Properly indented
      second line  # Properly indented
```

### Issue 3: Cloud-Init Only Runs Once

**Problem:** Fixed cloud-init config, but changes not applied after VM restart.

**Cause:** Cloud-init marks itself "done" after first boot. It checks `/var/lib/cloud/instance/` and skips if already completed.

**Solutions:**

1. **Full recreation** (cleanest):
   ```bash
   tofu destroy -target='proxmox_virtual_environment_vm.ubuntu_vm["vmname"]'
   tofu apply
   ```

2. **Manual state cleanup** (if VM must persist):
   ```bash
   # On Proxmox host, with VM stopped:
   guestmount -a /dev/pve/vm-<id>-disk-0 -i /tmp/vm
   rm -rf /tmp/vm/var/lib/cloud/instance/*
   rm -rf /tmp/vm/var/lib/cloud/data/*
   fusermount -u /tmp/vm
   qm start <id>
   ```

### Issue 4: Ubuntu 24.04 + EFI + IDE Incompatibility

**Problem:** Cloud-init not running on Ubuntu 24.04 VMs.

**Cause:** IDE cdrom and EFI BIOS don't work together for cloud-init.

**Solution:** Use compatible combinations:
- SeaBIOS + IDE (default, recommended)
- EFI + SCSI (if EFI required)

### Debugging Commands

```bash
# View cloud-init config Proxmox will generate
ssh root@proxmox 'qm cloudinit dump <vmid> user'

# Inspect actual cloud-init ISO content
ssh root@proxmox 'mkdir -p /tmp/ci && mount /dev/pve/vm-<vmid>-cloudinit /tmp/ci && cat /tmp/ci/user-data && umount /tmp/ci'

# Check cloud-init logs (requires VM disk mount)
ssh root@proxmox 'qm stop <vmid>'
ssh root@proxmox 'guestmount -a /dev/pve/vm-<vmid>-disk-0 -i /tmp/vm'
ssh root@proxmox 'cat /tmp/vm/var/log/cloud-init-output.log'
ssh root@proxmox 'fusermount -u /tmp/vm'

# Force cloud-init ISO regeneration
ssh root@proxmox 'qm cloudinit update <vmid>'

# Check cloud-init status (if SSH works)
ssh user@vm 'cloud-init status'
ssh user@vm 'cat /var/log/cloud-init-output.log'
```

### Template Best Practices

1. **Validate YAML before deployment:**
   ```bash
   tofu console <<< 'templatefile("templates/ubuntu-cloud-init.yaml.tpl", {...})' | yamllint -
   ```

2. **Use `replace()` for multiline content** in YAML literal blocks

3. **Test with minimal config first**, then add complexity

4. **Always check cloud-init logs** after first boot failures

## Operations

### Updating VM Configuration

For cloud-init changes to take effect on existing VMs:

```bash
# Option 1: Recreate VM (data loss!)
tofu apply -replace='proxmox_virtual_environment_vm.ubuntu_vm["vmname"]'

# Option 2: Update snippet only (requires manual cloud-init clean)
tofu apply -target='proxmox_virtual_environment_file.ubuntu_cloud_init["vmname"]'
# Then manually clean cloud-init state on VM
```

### NixOS VM Workflow

NixOS VMs use a two-phase deployment:

1. **Bootstrap:** Ubuntu VM created with minimal cloud-init (SSH only)
2. **Conversion:** nixos-anywhere installs NixOS over SSH
3. **Updates:** `nixos-rebuild` for subsequent changes

```bash
# Initial deployment
tofu apply  # Creates Ubuntu VM, runs nixos-anywhere

# Update NixOS config
nixos-rebuild switch --flake ../nixos#vmname --target-host root@<ip>
```

### Backup/Restore

VMs automatically back up `/opt/stacks/<stack>/config/` to NFS daily at 2am.

```bash
# Manual backup
ssh user@vm '/opt/stacks/backup-to-nfs.sh'

# Restore happens automatically on VM creation if backup exists
```

## File Structure

```
infrastructure/
├── main.tf                 # VM definitions, cloud-init resources
├── providers.tf            # Proxmox and 1Password provider config
├── secrets.tf              # 1Password data sources
├── variables.tf            # Input variable definitions
├── outputs.tf              # Output definitions
├── versions.tf             # Provider version constraints
├── terraform.tfvars        # Local configuration (gitignored)
└── templates/
    ├── ubuntu-cloud-init.yaml.tpl    # Full Ubuntu cloud-init
    ├── nixos-bootstrap.yaml.tpl      # Minimal NixOS bootstrap
    └── scripts/
        ├── install-docker.sh.tpl     # Docker installation
        ├── backup-to-nfs.sh.tpl      # NFS backup script
        └── restore-nfs-backup.sh.tpl # NFS restore script
```

## References

- [Proxmox Cloud-Init Support](https://pve.proxmox.com/wiki/Cloud-Init_Support)
- [Proxmox Cloud-Init FAQ](https://pve.proxmox.com/wiki/Cloud-Init_FAQ)
- [bpg/proxmox Terraform Provider](https://registry.terraform.io/providers/bpg/proxmox/latest/docs)
- [Ubuntu 24 Cloud-Init Issues (Forum)](https://forum.proxmox.com/threads/solved-proxmox-cloud-init-not-working-on-ubuntu-24-server-desktop.146078/)
- [Cloud-Init Documentation](https://cloudinit.readthedocs.io/)
