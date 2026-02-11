# =============================================================================
# Debian Cloud Image Download
# =============================================================================
# Downloaded once per Proxmox node and used as import source for all VMs.
# overwrite = false prevents re-downloading the "latest" URL on every apply.
# =============================================================================

resource "proxmox_virtual_environment_download_file" "debian_cloud_image" {
  for_each     = local.proxmox_nodes
  content_type = "import"
  datastore_id = "local"
  node_name    = each.key
  file_name    = "debian-12-generic-amd64.qcow2"
  url          = "https://cloud.debian.org/images/cloud/bookworm/latest/debian-12-generic-amd64.qcow2"
  overwrite    = false
}
