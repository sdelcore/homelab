# =============================================================================
# VM Definitions
# =============================================================================
# Architecture:
#   - All VM config is defined in ../hosts.json (single source of truth)
#   - VMs cloned from Debian cloud image template (cloud-init for SSH+IP)
#   - nixos-anywhere installs NixOS over SSH
#   - Colmena manages ongoing NixOS configuration
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

# =============================================================================
# VMs (cloned from Debian cloud image, then nixos-anywhere installs NixOS)
# =============================================================================
# Workflow:
# 1. One-time: ./scripts/setup-cloud-template.sh (create Debian template)
# 2. OpenTofu clones VMs from Debian template (cloud-init sets SSH keys + IP)
# 3. nixos-anywhere installs NixOS: ./scripts/deploy.sh --nixos-anywhere
# 4. Colmena deploys configuration: colmena apply
# =============================================================================

# Clone VMs from Debian cloud image template
resource "proxmox_virtual_environment_vm" "nixos_vm" {
  for_each = local.nixos_vms

  name        = each.key
  node_name   = each.value.node
  vm_id       = each.value.vm_id
  description = "NixOS host managed by Colmena"
  tags        = ["tofu", "docker", "nixos"]

  on_boot         = true
  stop_on_destroy = true

  # Clone from Debian cloud image template
  clone {
    vm_id = var.cloud_template_vmid
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

  # Cloud-init for initial network and SSH key config
  initialization {
    datastore_id = var.vm_storage

    user_account {
      keys = var.ssh_public_keys
    }

    ip_config {
      ipv4 {
        address = each.value.ip
        gateway = local.gateway
      }
    }
  }

  lifecycle {
    ignore_changes = [
      # Ignore changes managed by Colmena/nixos-anywhere
      initialization,
      clone,
    ]
  }
}

# =============================================================================
# GPU VMs (with PCI passthrough)
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

  # Clone from Debian cloud image template
  clone {
    vm_id = var.cloud_template_vmid
  }

  agent {
    enabled = true
    timeout = "2m"
  }

  operating_system {
    type = "l26"
  }

  serial_device {}

  # Minimal VGA for Proxmox console access (GPU passthrough still works for compute)
  vga {
    type   = "std"
    memory = 16
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

  # Cloud-init for initial network and SSH key config
  initialization {
    datastore_id = var.vm_storage

    user_account {
      keys = var.ssh_public_keys
    }

    ip_config {
      ipv4 {
        address = each.value.ip
        gateway = local.gateway
      }
    }
  }

  lifecycle {
    ignore_changes = [
      # Ignore changes managed by Colmena/nixos-anywhere
      initialization,
      clone,
    ]
  }
}
