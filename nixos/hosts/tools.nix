# tools VM - Utility tools stack
#
# Services: Traefik, Termix (SSH web UI), Homepage, Stirling PDF
{ ... }:
{
  imports = [
    ../modules/homepage.nix
  ];

  # ============================================================
  # Docker Stack Overrides
  # ============================================================
  dockerStack.extraPorts = [
    80 8080 # Traefik
  ];

  # ============================================================
  # Homepage Configuration (declarative)
  # ============================================================
  homepage.enable = true;
}
