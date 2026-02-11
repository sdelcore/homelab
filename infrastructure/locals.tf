# =============================================================================
# VM Definitions
# =============================================================================
# Architecture:
#   - All VM config is defined in ../artifacts/hosts.json (single source of truth)
#   - OpenTofu downloads Debian cloud image and imports it into each VM
#   - nixos-anywhere installs NixOS over SSH
#   - Colmena manages ongoing NixOS configuration
# =============================================================================

locals {
  # ---------------------------------------------------------------------------
  # Load host configuration from shared JSON file
  # ---------------------------------------------------------------------------
  hosts_config = jsondecode(file("${path.module}/../artifacts/hosts.json"))

  # Network configuration
  gateway = local.hosts_config.network.gateway

  # NFS configuration
  nfs_server      = local.hosts_config.nfs.server
  nfs_export      = local.hosts_config.nfs.export
  nfs_docker_data = "docker-data"

  # ---------------------------------------------------------------------------
  # All NixOS VMs (GPU and non-GPU)
  # ---------------------------------------------------------------------------
  nixos_vms = {
    for name, host in local.hosts_config.hosts : name => {
      node        = host.node
      vm_id       = host.vmId
      ip          = "${host.ip}/${local.hosts_config.network.prefixLength}"
      mac_address = host.mac
      cores       = host.cores
      memory      = host.memory
      disk_gb     = host.disk
      domain      = host.domain
      gpu         = host.gpu
      gpu_id      = try(host.gpuId, null)
    }
  }

  # ---------------------------------------------------------------------------
  # Unique Proxmox nodes (for downloading cloud image once per node)
  # ---------------------------------------------------------------------------
  proxmox_nodes = toset([for name, host in local.hosts_config.hosts : host.node])
}

# =============================================================================
# Infrastructure Devices (not managed by OpenTofu)
# =============================================================================
# Shared definition used by both DNS and DHCP configurations.
# Devices with mac = null are included in DNS but excluded from DHCP.

locals {
  infra_devices = {
    pfsense = {
      ip  = "10.0.0.1"
      mac = null # DHCP server itself — no static mapping
    }
    pihole = {
      ip  = "10.0.0.18"
      mac = "XX:XX:XX:XX:XX:XX" # TODO: fill in actual MAC
    }
    tower = {
      ip  = "10.0.0.5"
      mac = "XX:XX:XX:XX:XX:XX" # TODO: fill in actual MAC
    }
    strongbad = {
      ip  = "10.0.0.10"
      mac = "XX:XX:XX:XX:XX:XX" # TODO: fill in actual MAC
    }
    strongmad = {
      ip  = "10.0.0.11"
      mac = "XX:XX:XX:XX:XX:XX" # TODO: fill in actual MAC
    }
    strongsad = {
      ip  = "10.0.0.12"
      mac = "XX:XX:XX:XX:XX:XX" # TODO: fill in actual MAC
    }
  }
}
