# Cloud-Init Troubleshooting

Detailed troubleshooting for Ubuntu VMs using cloud-init on Proxmox.

## Common Issues

### Issue 1: Provider Conflict

**Problem:** SSH keys not being applied to VMs.

**Cause:** The bpg/proxmox provider's `user_account` block conflicts with `user_data_file_id`. You cannot use both simultaneously.

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

## Debugging Commands

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

## Template Best Practices

1. **Validate YAML before deployment:**
   ```bash
   tofu console <<< 'templatefile("templates/ubuntu-cloud-init.yaml.tpl", {...})' | yamllint -
   ```

2. **Use `replace()` for multiline content** in YAML literal blocks

3. **Test with minimal config first**, then add complexity

4. **Always check cloud-init logs** after first boot failures

## References

- [Proxmox Cloud-Init Support](https://pve.proxmox.com/wiki/Cloud-Init_Support)
- [Proxmox Cloud-Init FAQ](https://pve.proxmox.com/wiki/Cloud-Init_FAQ)
- [Ubuntu 24 Cloud-Init Issues (Forum)](https://forum.proxmox.com/threads/solved-proxmox-cloud-init-not-working-on-ubuntu-24-server-desktop.146078/)
- [Cloud-Init Documentation](https://cloudinit.readthedocs.io/)
