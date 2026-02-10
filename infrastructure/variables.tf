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

# =============================================================================
# Networking
# =============================================================================
variable "vm_bridge" {
  description = "Network bridge"
  type        = string
  default     = "vmbr0"
}

# =============================================================================
# SSH Keys
# =============================================================================
variable "ssh_public_keys" {
  description = "List of SSH public keys for the user"
  type        = list(string)
  default     = []
}

# =============================================================================
# Cloud Image Template
# =============================================================================
variable "cloud_template_vmid" {
  description = "VM ID of the Debian cloud image template (created by setup-cloud-template.sh)"
  type        = number
  default     = 9000
}
