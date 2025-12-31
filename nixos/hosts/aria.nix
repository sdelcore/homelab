# aria VM - ARIA APK update server + Mem video processing
#
# Services: Traefik, Nginx (APK server), Mem (backend, frontend, RTMP)
{ config, pkgs, lib, stacksPath, hostsConfig, networkConfig, ... }:

let
  hostName = "aria";
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
    enableTcp = false;
    extraPorts = [
      80 8080 # Traefik
      1935    # RTMP streaming
    ];
  };

  # ============================================================
  # Ensure directories exist
  # ============================================================
  systemd.tmpfiles.rules = [
    "d /opt/stacks/${hostName}/public 0755 root root -"
    # Mem directories
    "d /opt/stacks/${hostName}/config/mem 0755 root root -"
    "d /opt/stacks/${hostName}/data/mem 0755 root root -"
    "d /opt/stacks/${hostName}/data/mem/db 0755 root root -"
    "d /opt/stacks/${hostName}/data/mem/uploads 0755 root root -"
    "d /opt/stacks/${hostName}/data/mem/streams 0755 root root -"
  ];

  # ============================================================
  # NFS Backup (enabled for mem data)
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
