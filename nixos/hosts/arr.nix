# arr VM - Media automation stack
#
# Services: Traefik, Gluetun (VPN), Deluge, SABnzbd, Prowlarr,
#           Jackett, FlareSolverr, Sonarr, Radarr, Jellyseerr
{ ... }:
{
  # ============================================================
  # Docker Stack Overrides
  # ============================================================
  dockerStack = {
    enableTcp = true; # For Homepage discovery from tools VM
    extraPorts = [
      80 8080 # Traefik
      8112 # Deluge web UI (via gluetun)
      8081 # SABnzbd
      9696 # Prowlarr
      9117 # Jackett
      8191 # FlareSolverr
      8989 # Sonarr
      7878 # Radarr
      5055 # Jellyseerr
      58846
      58946 # Deluge daemon ports
    ];
  };
}
