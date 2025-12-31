# =============================================================================
# VM Definitions
# =============================================================================
# Architecture:
#   - All VM config is defined in ../hosts.json (single source of truth)
#   - NixOS VMs: Cloned from template, configured by Colmena
#   - Ubuntu templates kept in templates/ for reference only
# =============================================================================

locals {
  # ---------------------------------------------------------------------------
  # Load host configuration from shared JSON file
  # ---------------------------------------------------------------------------
  hosts_config = jsondecode(file("${path.module}/../nixos/hosts.json"))

  # Network configuration
  gateway = local.hosts_config.network.gateway

  # NFS configuration
  nfs_server      = local.hosts_config.nfs.server
  nfs_export      = local.hosts_config.nfs.export
  nfs_docker_data = "docker-data"

  # ---------------------------------------------------------------------------
  # NixOS VMs (cloned from template, configured by Colmena)
  # ---------------------------------------------------------------------------
  # Filter hosts without GPU
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
  # NixOS GPU VMs (with PCI passthrough)
  # ---------------------------------------------------------------------------
  # Filter hosts with GPU
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

  # ---------------------------------------------------------------------------
  # NixOS template VMIDs per node
  # ---------------------------------------------------------------------------
  # strongmad: 9000 (NFS shared storage)
  # strongbad: 9002 (local-lvm storage - more reliable for GPU VMs)
  nixos_template_vmids = {
    strongmad = 9000
    strongbad = 9002
  }
}

# =============================================================================
# NIXOS VMs (cloned from template, configured by Colmena)
# =============================================================================
# Workflow:
# 1. Build NixOS image: nix build ./nixos#proxmox-image
# 2. Upload to Proxmox: ./scripts/upload-nixos-image.sh
# 3. OpenTofu clones VMs from template
# 4. Colmena deploys configuration: colmena apply
# =============================================================================

# Clone NixOS VMs from template
resource "proxmox_virtual_environment_vm" "nixos_vm" {
  for_each = local.nixos_vms

  name        = each.key
  node_name   = each.value.node
  vm_id       = each.value.vm_id
  description = "NixOS host managed by Colmena"
  tags        = ["tofu", "docker", "nixos"]

  on_boot         = true
  stop_on_destroy = true

  # Clone from NixOS template
  clone {
    vm_id = var.nixos_template_vmid
  }

  agent {
    enabled = true
    timeout = "2m"
  }

  operating_system {
    type = "l26"
  }

  serial_device {}

  vga {
    type = "std"
  }

  cpu {
    cores = each.value.cores
    type  = "host"
  }

  memory {
    dedicated = each.value.memory
  }

  rng {
    source = "/dev/urandom"
  }

  # Resize disk from template size
  disk {
    datastore_id = var.vm_storage
    interface    = "virtio0"
    size         = each.value.disk_gb
    iothread     = true
    discard      = "on"
  }

  network_device {
    bridge      = var.vm_bridge
    model       = "virtio"
    mac_address = each.value.mac_address
  }

  # Cloud-init for initial network config (DHCP)
  # Static IP is set by Colmena after first boot
  initialization {
    datastore_id = var.vm_storage

    ip_config {
      ipv4 {
        address = each.value.ip
        gateway = local.gateway
      }
    }
  }

  lifecycle {
    ignore_changes = [
      # Ignore changes managed by Colmena
      initialization,
      clone,
    ]
  }
}

# =============================================================================
# NIXOS GPU VMs (with PCI passthrough)
# =============================================================================
# These VMs use q35 machine type for PCIe passthrough and have GPU attached.
# Prerequisite: Create PCI resource mapping in Proxmox UI before applying.
# =============================================================================

resource "proxmox_virtual_environment_vm" "nixos_gpu_vm" {
  for_each = local.nixos_gpu_vms

  name        = each.key
  node_name   = each.value.node
  vm_id       = each.value.vm_id
  description = "NixOS GPU host managed by Colmena"
  tags        = ["tofu", "docker", "nixos", "gpu"]

  on_boot         = true
  stop_on_destroy = true

  # q35 machine type required for PCIe passthrough
  machine = "q35"

  # Clone from NixOS template (node-specific, but all share same NFS disk)
  clone {
    vm_id = local.nixos_template_vmids[each.value.node]
  }

  agent {
    enabled = true
    timeout = "2m"
  }

  operating_system {
    type = "l26"
  }

  serial_device {}

  # Disable VGA since GPU is passed through
  vga {
    type = "none"
  }

  cpu {
    cores = each.value.cores
    type  = "host"
  }

  memory {
    dedicated = each.value.memory
  }

  rng {
    source = "/dev/urandom"
  }

  # Resize disk from template size
  disk {
    datastore_id = var.vm_storage
    interface    = "virtio0"
    size         = each.value.disk_gb
    iothread     = true
    discard      = "on"
  }

  network_device {
    bridge      = var.vm_bridge
    model       = "virtio"
    mac_address = each.value.mac_address
  }

  # GPU passthrough via direct PCI device ID
  # Note: rombar=false is required to prevent boot hangs with NVIDIA GPUs
  hostpci {
    device = "hostpci0"
    id     = each.value.gpu_id
    pcie   = true
    rombar = false
    xvga   = false
  }

  # Cloud-init for initial network config
  initialization {
    datastore_id = var.vm_storage

    ip_config {
      ipv4 {
        address = each.value.ip
        gateway = local.gateway
      }
    }
  }

  lifecycle {
    ignore_changes = [
      # Ignore changes managed by Colmena
      initialization,
      clone,
    ]
  }
}
