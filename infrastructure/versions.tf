terraform {
  required_version = ">= 1.6.0" # OpenTofu version

  required_providers {
    proxmox = {
      source  = "bpg/proxmox"
      version = ">= 0.53.1"
    }
    onepassword = {
      source  = "1Password/onepassword"
      version = "~> 2.0"
    }
    pfsense = {
      source  = "marshallford/pfsense"
      version = "~> 0.20"
    }
  }
}
