provider "proxmox" {
  endpoint  = var.proxmox.api_url
  api_token = "${var.proxmox.api_token_id}=${var.proxmox.api_token_secret}"
  insecure  = var.proxmox.tls_insecure

  ssh {
    agent    = true
    username = "root"
  }
}

# 1Password provider for secrets management
# Requires OP_SERVICE_ACCOUNT_TOKEN environment variable
provider "onepassword" {}

# pfSense for DNS management
provider "pfsense" {
  url             = var.pfsense.url
  username        = var.pfsense.username
  password        = var.pfsense.password
  tls_skip_verify = var.pfsense.tls_skip_verify
}
