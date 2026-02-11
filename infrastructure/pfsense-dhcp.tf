# =============================================================================
# DHCP Static Mappings (pfSense)
# =============================================================================
# Manages DHCP static mappings (MAC → IP) on pfSense for both VMs and
# infrastructure devices. All mappings use apply = false so changes are
# batched and applied once via pfsense_dhcpv4_apply.

# ---------------------------------------------------------------------------
# VM DHCP mappings (from hosts.json)
# ---------------------------------------------------------------------------
resource "pfsense_dhcpv4_staticmapping" "vm" {
  for_each = local.hosts_config.hosts

  interface   = "lan"
  mac_address = each.value.mac
  ip_address  = each.value.ip
  hostname    = each.key
  description = "NixOS VM: ${each.key}"
  apply       = false
}

# ---------------------------------------------------------------------------
# Infrastructure DHCP mappings (derived from shared infra_devices)
# ---------------------------------------------------------------------------
resource "pfsense_dhcpv4_staticmapping" "infra" {
  for_each = {
    for name, dev in local.infra_devices : name => dev
    if dev.mac != null
  }

  interface   = "lan"
  mac_address = each.value.mac
  ip_address  = each.value.ip
  hostname    = each.key
  description = "Infrastructure: ${each.key}"
  apply       = false
}

# ---------------------------------------------------------------------------
# Apply DHCP changes (single reload after all mappings are updated)
# ---------------------------------------------------------------------------
resource "pfsense_dhcpv4_apply" "lan" {
  interface = "lan"

  lifecycle {
    replace_triggered_by = [
      pfsense_dhcpv4_staticmapping.vm,
      pfsense_dhcpv4_staticmapping.infra,
    ]
  }
}
