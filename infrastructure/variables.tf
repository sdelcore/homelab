# =============================================================================
# Proxmox Connection
# =============================================================================
variable "proxmox" {
  description = "Proxmox connection configuration"
  type = object({
    api_url          = string
    api_token_id     = string
    api_token_secret = string
    tls_insecure     = optional(bool, true)
  })
  sensitive = true
}

# =============================================================================
# VM Defaults
# =============================================================================
variable "vm" {
  description = "VM default configuration"
  type = object({
    storage = optional(string, "local-lvm")
    bridge  = optional(string, "vmbr0")
  })
}

# =============================================================================
# SSH Keys
# =============================================================================
variable "ssh_public_keys" {
  description = "SSH public keys for VM access"
  type        = list(string)
  default     = []
}
