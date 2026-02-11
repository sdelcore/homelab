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
  # Non-GPU VMs
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
    } if !host.gpu
  }

  # ---------------------------------------------------------------------------
  # Unique Proxmox nodes (for downloading cloud image once per node)
  # ---------------------------------------------------------------------------
  proxmox_nodes = toset([for name, host in local.hosts_config.hosts : host.node])

  # ---------------------------------------------------------------------------
  # GPU VMs (with PCI passthrough)
  # ---------------------------------------------------------------------------
  nixos_gpu_vms = {
    for name, host in local.hosts_config.hosts : name => {
      node        = host.node
      vm_id       = host.vmId
      ip          = "${host.ip}/${local.hosts_config.network.prefixLength}"
      mac_address = host.mac
      cores       = host.cores
      memory      = host.memory
      disk_gb     = host.disk
      domain      = host.domain
      gpu_id      = host.gpuId
    } if host.gpu
  }
}
