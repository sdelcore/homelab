# arr VM - Media automation stack
#
# Services: Traefik, Gluetun (VPN), Deluge, SABnzbd, Prowlarr,
#           Jackett, FlareSolverr, Sonarr, Radarr, Jellyseerr
{ config, pkgs, lib, stacksPath, hostsConfig, networkConfig, ... }:

let
  hostName = "arr";
  hostConfig = hostsConfig.hosts.${hostName};
in
{
  # ============================================================
  # Network Configuration (from hosts.json)
  # ============================================================
  networking.hostName = hostName;
  networking.useDHCP = false;
  networking.interfaces.eth0.ipv4.addresses = [{
    address = hostConfig.ip;
    prefixLength = networkConfig.prefixLength;
  }];
  networking.defaultGateway = networkConfig.gateway;
  networking.nameservers = networkConfig.nameservers;

  # ============================================================
  # Docker Stack
  # ============================================================
  dockerStack = {
    enable = true;
    stackName = hostName;
    composeFile = stacksPath + "/${hostName}/compose.yml";
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
    stackName = hostName;
  };

  # ============================================================
  # Colmena Deployment Settings
  # ============================================================
  deployment = {
    targetHost = hostConfig.ip;
    targetUser = "root";
    tags = hostConfig.tags;

    # Secret: .env file from 1Password
    # Colmena will run `op read ...` locally and upload the result
    keys."stack-env" = {
      keyCommand = [ "op" "read" "op://Infrastructure/env-${hostName}-stack/notesPlain" ];
      destDir = "/opt/stacks/${hostName}";
      name = ".env";
      user = "root";
      group = "root";
      permissions = "0600";
    };
  };
}
