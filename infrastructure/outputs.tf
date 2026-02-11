# =============================================================================
# VM Outputs
# =============================================================================

output "nixos_vms" {
  description = "Map of NixOS VM information"
  value = {
    for name, vm in proxmox_virtual_environment_vm.nixos_vm : name => {
      vm_id = vm.vm_id
      name  = vm.name
      ip    = local.hosts_config.hosts[name].ip
    }
  }
}

# =============================================================================
# Colmena Helper
# =============================================================================

output "colmena_hosts" {
  description = "NixOS hosts for Colmena deployment"
  value = {
    for name, host in local.hosts_config.hosts : name => {
      ip   = host.ip
      tags = host.tags
    }
  }
}
