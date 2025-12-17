# =============================================================================
# VM Definitions
# =============================================================================
# Architecture:
#   - NixOS VMs: Cloned from template, configured by Colmena
#   - Ubuntu VM: Cloud-init provisioned, for Portainer reference
# =============================================================================

locals {
  # ---------------------------------------------------------------------------
  # Ubuntu VMs (cloud-init provisioned)
  # ---------------------------------------------------------------------------
  # Reference VM for demonstrating cloud-init + Docker Compose
  ubuntu_vms = {
    portainer = {
      node        = "strongmad"
      vm_id       = 202
      ip          = "10.0.0.22/24"
      mac_address = "BC:24:11:00:00:16"
      cores       = 2
      memory      = 2048
      disk_gb     = 20
      stack       = "portainer"
      domain      = "portainer.tap"
      docker_tcp  = false
    }
  }

  # ---------------------------------------------------------------------------
  # NixOS VMs (cloned from template, configured by Colmena)
  # ---------------------------------------------------------------------------
  # These VMs are provisioned from a NixOS template image built with
  # nixos-generators. After boot, Colmena deploys the full configuration.
  nixos_vms = {
    arr = {
      node        = "strongmad"
      vm_id       = 200
      ip          = "10.0.0.20/24"
      mac_address = "BC:24:11:00:00:14"
      cores       = 4
      memory      = 4096
      disk_gb     = 50
      domain      = "arr.tap"
    }
    tools = {
      node        = "strongmad"
      vm_id       = 201
      ip          = "10.0.0.21/24"
      mac_address = "BC:24:11:00:00:15"
      cores       = 2
      memory      = 2048
      disk_gb     = 30
      domain      = "tools.tap"
    }
  }

  # ---------------------------------------------------------------------------
  # Shared Configuration
  # ---------------------------------------------------------------------------
  gateway = "10.0.0.1"

  # Derive which nodes need each image type
  ubuntu_nodes = toset([for vm in local.ubuntu_vms : vm.node])

  # NFS server for persistent data
  nfs_server      = "10.0.0.5"
  nfs_export      = "/mnt/user/infrastructure"
  nfs_docker_data = "docker-data"

  # Read compose files at apply time (embedded in cloud-init for Ubuntu VMs)
  stack_compose_content = {
    portainer = file("${path.module}/../stacks/portainer/compose.yml")
  }
}

# =============================================================================
# CLOUD IMAGES
# =============================================================================

# Download Ubuntu Cloud Image for Ubuntu VMs
resource "proxmox_virtual_environment_download_file" "ubuntu_cloud_image" {
  for_each = local.ubuntu_nodes

  content_type = "iso"
  datastore_id = var.snippet_storage
  node_name    = each.value
  url          = var.ubuntu_image_url
  file_name    = "ubuntu-24.04-cloud.img"
}

# =============================================================================
# UBUNTU VMs (Portainer reference)
# =============================================================================

# Ubuntu Cloud-init User Data Snippets
resource "proxmox_virtual_environment_file" "ubuntu_cloud_init" {
  for_each = local.ubuntu_vms

  content_type = "snippets"
  datastore_id = var.snippet_storage
  node_name    = each.value.node

  source_raw {
    data = templatefile("${path.module}/templates/ubuntu-cloud-init.yaml.tpl", {
      hostname        = each.key
      username        = var.vm_user
      ssh_keys        = var.ssh_public_keys
      timezone        = "America/Toronto"
      stack           = each.value.stack
      nfs_server      = local.nfs_server
      nfs_docker_data = local.nfs_docker_data
      env_content     = local.stack_env_content[each.value.stack]
      compose_content = local.stack_compose_content[each.value.stack]

      # Home-manager deployment (disabled for portainer)
      enable_home_manager = false
      nixos_flake_repo    = ""

      # Docker TCP for remote discovery
      enable_docker_tcp = try(each.value.docker_tcp, false)

      # Provisioning scripts (embedded at apply time)
      install_docker_script = file("${path.module}/templates/scripts/install-docker.sh.tpl")
      restore_nfs_script = templatefile("${path.module}/templates/scripts/restore-nfs-backup.sh.tpl", {
        stack           = each.value.stack
        nfs_server      = local.nfs_server
        nfs_export      = local.nfs_export
        nfs_docker_data = local.nfs_docker_data
      })
      backup_nfs_script = templatefile("${path.module}/templates/scripts/backup-to-nfs.sh.tpl", {
        stack           = each.value.stack
        nfs_server      = local.nfs_server
        nfs_export      = local.nfs_export
        nfs_docker_data = local.nfs_docker_data
      })
    })
    file_name = "${each.key}-user-data.yaml"
  }
}

# Ubuntu Virtual Machines
resource "proxmox_virtual_environment_vm" "ubuntu_vm" {
  for_each = local.ubuntu_vms

  name        = each.key
  node_name   = each.value.node
  vm_id       = each.value.vm_id
  description = "Ubuntu Docker host managed by OpenTofu (reference VM)"
  tags        = ["tofu", "docker", "ubuntu"]

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

  disk {
    datastore_id = var.vm_storage
    interface    = "virtio0"
    size         = each.value.disk_gb
    iothread     = true
    discard      = "on"
    file_id      = proxmox_virtual_environment_download_file.ubuntu_cloud_image[each.value.node].id
  }

  network_device {
    bridge      = var.vm_bridge
    model       = "virtio"
    mac_address = each.value.mac_address
  }

  initialization {
    datastore_id      = var.vm_storage
    user_data_file_id = proxmox_virtual_environment_file.ubuntu_cloud_init[each.key].id

    ip_config {
      ipv4 {
        address = each.value.ip
        gateway = local.gateway
      }
    }
  }

  lifecycle {
    ignore_changes = [
      initialization[0].user_account,
    ]
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
