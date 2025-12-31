# =============================================================================
# Proxmox Connection
# =============================================================================
variable "proxmox_api_url" {
  description = "Proxmox API URL (e.g., https://proxmox.local:8006/api2/json)"
  type        = string
  sensitive   = true
}

variable "proxmox_api_token_id" {
  description = "Proxmox API Token ID (e.g., terraform@pve!terraform-token)"
  type        = string
  sensitive   = true
}

variable "proxmox_api_token_secret" {
  description = "Proxmox API Token Secret"
  type        = string
  sensitive   = true
}

variable "proxmox_tls_insecure" {
  description = "Skip TLS verification for self-signed certificates"
  type        = bool
  default     = true
}

# =============================================================================
# Proxmox Node
# =============================================================================
variable "proxmox_node" {
  description = "Proxmox node name to deploy VM on"
  type        = string
  default     = "pve"
}

# =============================================================================
# Storage
# =============================================================================
variable "vm_storage" {
  description = "Proxmox storage for VM disk"
  type        = string
  default     = "local-lvm"
}

variable "snippet_storage" {
  description = "Proxmox storage for cloud-init snippets (must support snippets)"
  type        = string
  default     = "local"
}

# =============================================================================
# Networking
# =============================================================================
variable "vm_bridge" {
  description = "Network bridge"
  type        = string
  default     = "vmbr0"
}

# =============================================================================
# User Configuration
# =============================================================================
variable "vm_user" {
  description = "Default user for VMs (used by cloud-init templates)"
  type        = string
  default     = "sdelcore"
}

variable "ssh_public_keys" {
  description = "List of SSH public keys for the user"
  type        = list(string)
  default     = []
}

# =============================================================================
# Cloud Images
# =============================================================================
variable "ubuntu_image_url" {
  description = "URL to Ubuntu cloud image"
  type        = string
  default     = "https://cloud-images.ubuntu.com/noble/current/noble-server-cloudimg-amd64.img"
}

# =============================================================================
# NixOS Template
# =============================================================================
variable "nixos_template_vmid" {
  description = "VM ID of the NixOS template (created by upload-nixos-image.sh)"
  type        = number
  default     = 9000
}

variable "nixos_template_storage" {
  description = "Proxmox storage for NixOS template (shared storage for multi-node access)"
  type        = string
  default     = "nfs-infrastructure"
}

# =============================================================================
# 1Password
# =============================================================================
variable "onepassword_vault" {
  description = "1Password vault name containing stack secrets"
  type        = string
  default     = "Infrastructure"
}
