# aria VM - ARIA APK update server
#
# Services: Traefik, Nginx (APK server)
{ name, ... }:
{
  # ============================================================
  # Docker Stack Overrides
  # ============================================================
  dockerStack.extraPorts = [
    80 443 8080 # Traefik (HTTP, HTTPS, Dashboard)
  ];

  # ============================================================
  # Ensure directories exist
  # ============================================================
  systemd.tmpfiles.rules = [
    "d /opt/stacks/${name}/public 0755 root root -"
  ];
}
