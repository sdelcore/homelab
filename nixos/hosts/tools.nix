# tools VM - Utility tools stack
#
# Services: Traefik, Termix (SSH web UI), Homepage, Stirling PDF
{ config, pkgs, lib, stacksPath, ... }:

{
  imports = [
    ../modules/homepage.nix
  ];

  # ============================================================
  # Network Configuration
  # ============================================================
  networking.hostName = "tools";
  networking.useDHCP = false;
  networking.interfaces.ens18.ipv4.addresses = [{
    address = "10.0.0.21";
    prefixLength = 24;
  }];
  networking.defaultGateway = "10.0.0.1";
  networking.nameservers = [ "1.1.1.1" "8.8.8.8" ];

  # ============================================================
  # Docker Stack
  # ============================================================
  dockerStack = {
    enable = true;
    stackName = "tools";
    composeFile = stacksPath + "/tools/compose.yml";
    enableTcp = false;
    extraPorts = [
      80 8080 # Traefik
    ];
  };

  # ============================================================
  # Homepage Configuration (declarative)
  # ============================================================
  homepage.enable = true;

  # ============================================================
  # NFS Backup
  # ============================================================
  nfsBackup = {
    enable = true;
    stackName = "tools";
  };

  # ============================================================
  # Colmena Deployment Settings
  # ============================================================
  deployment = {
    targetHost = "10.0.0.21";
    targetUser = "root";
    tags = [ "docker" "tools" "nixos" ];

    # Secret: .env file from 1Password
    keys."stack-env" = {
      keyCommand = [ "op" "read" "op://Infrastructure/env-tools-stack/notesPlain" ];
      destDir = "/opt/stacks/tools";
      name = ".env";
      user = "root";
      group = "root";
      permissions = "0600";
    };
  };
}
