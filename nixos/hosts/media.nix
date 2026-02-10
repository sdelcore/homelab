# media VM - Plex Media Server with GPU Hardware Transcoding
#
# Services: Plex (media streaming with PlexPass HW transcoding)
# GPU: NVIDIA T400 via PCI passthrough
{ ... }:
{
  # ============================================================
  # Docker Stack Overrides
  # ============================================================
  dockerStack.extraPorts = [
    80          # Traefik HTTP
    8080        # Traefik Dashboard
    32400       # Plex (host networking)
  ];
}
