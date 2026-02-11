# =============================================================================
# VMs (Debian cloud image + nixos-anywhere installs NixOS)
# =============================================================================
# Workflow:
# 1. OpenTofu downloads Debian cloud image and creates VMs (cloud-init sets SSH keys + IP)
# 2. nixos-anywhere installs NixOS over SSH: just install <host>
# 3. Colmena deploys configuration: just deploy
# =============================================================================

resource "proxmox_virtual_environment_vm" "nixos_vm" {
  for_each = local.nixos_vms

  name        = each.key
  node_name   = each.value.node
  vm_id       = each.value.vm_id
  description = "NixOS host managed by Colmena"
  tags        = ["tofu", "docker", "nixos"]

  on_boot         = true
  stop_on_destroy = true

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

  # Import disk from downloaded Debian cloud image
  disk {
    datastore_id = var.vm.storage
    interface    = "virtio0"
    size         = each.value.disk_gb
    iothread     = true
    discard      = "on"
    import_from  = proxmox_virtual_environment_download_file.debian_cloud_image[each.value.node].id
  }

  network_device {
    bridge      = var.vm.bridge
    model       = "virtio"
    mac_address = each.value.mac_address
  }

  # Cloud-init for initial network and SSH key config
  initialization {
    datastore_id = var.vm.storage

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
      disk[0].import_from,
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

  # Import disk from downloaded Debian cloud image
  disk {
    datastore_id = var.vm.storage
    interface    = "virtio0"
    size         = each.value.disk_gb
    iothread     = true
    discard      = "on"
    import_from  = proxmox_virtual_environment_download_file.debian_cloud_image[each.value.node].id
  }

  network_device {
    bridge      = var.vm.bridge
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
    datastore_id = var.vm.storage

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
      disk[0].import_from,
    ]
  }
}
