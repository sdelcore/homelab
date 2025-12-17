# arr VM - Media automation stack
#
# Services: Traefik, Gluetun (VPN), Deluge, SABnzbd, Prowlarr,
#           Jackett, FlareSolverr, Sonarr, Radarr, Jellyseerr
{ config, pkgs, lib, stacksPath, ... }:

{
  # ============================================================
  # Network Configuration
  # ============================================================
  networking.hostName = "arr";
  networking.useDHCP = false;
  networking.interfaces.eth0.ipv4.addresses = [{
    address = "10.0.0.20";
    prefixLength = 24;
  }];
  networking.defaultGateway = "10.0.0.1";
  networking.nameservers = [ "1.1.1.1" "8.8.8.8" ];

  # ============================================================
  # Docker Stack
  # ============================================================
  dockerStack = {
    enable = true;
    stackName = "arr";
    composeFile = stacksPath + "/arr/compose.yml";
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

  # ============================================================
  # NFS Backup
  # ============================================================
  nfsBackup = {
    enable = true;
    stackName = "arr";
  };

  # ============================================================
  # Colmena Deployment Settings
  # ============================================================
  deployment = {
    targetHost = "10.0.0.20";
    targetUser = "root";
    tags = [ "docker" "media" "nixos" ];

    # Secret: .env file from 1Password
    # Colmena will run `op read ...` locally and upload the result
    keys."stack-env" = {
      keyCommand = [ "op" "read" "op://Infrastructure/env-arr-stack/notesPlain" ];
      destDir = "/opt/stacks/arr";
      name = ".env";
      user = "root";
      group = "root";
      permissions = "0600";
    };
  };
}
