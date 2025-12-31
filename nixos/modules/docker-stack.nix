# Docker stack deployment module
#
# Provides a declarative way to deploy Docker Compose stacks on NixOS.
# The compose.yml is copied from the stacks/ directory and a systemd
# service manages the stack lifecycle.
{ config, pkgs, lib, ... }:

with lib;

let
  cfg = config.dockerStack;
in
{
  options.dockerStack = {
    enable = mkEnableOption "Docker Compose stack deployment";

    stackName = mkOption {
      type = types.str;
      description = "Name of the stack (arr, tools, etc.)";
    };

    composeFile = mkOption {
      type = types.path;
      description = "Path to compose.yml file";
    };

    enableTcp = mkOption {
      type = types.bool;
      default = false;
      description = "Enable Docker TCP socket (port 2375) for remote access (e.g., Homepage discovery)";
    };

    extraPorts = mkOption {
      type = types.listOf types.int;
      default = [ ];
      description = "Additional firewall ports to open for this stack";
    };
  };

  config = mkIf cfg.enable {
    # ============================================================
    # Docker Configuration
    # ============================================================
    virtualisation.docker = {
      enable = true;
      autoPrune = {
        enable = true;
        dates = "weekly";
      };
      daemon.settings = mkMerge [
        # Always configure insecure registry for local registry access
        { insecure-registries = [ "registry.sdelcore.com" ]; }
        # Docker TCP socket (optional, for Homepage remote discovery)
        (mkIf cfg.enableTcp {
          hosts = [ "unix:///var/run/docker.sock" "tcp://0.0.0.0:2375" ];
        })
      ];
    };

    # Override default docker service when TCP is enabled
    # (default only binds to unix socket)
    systemd.services.docker.serviceConfig = mkIf cfg.enableTcp {
      ExecStart = mkForce [
        ""
        "${pkgs.docker}/bin/dockerd"
      ];
    };

    # ============================================================
    # Firewall
    # ============================================================
    networking.firewall.allowedTCPPorts =
      cfg.extraPorts ++ (optionals cfg.enableTcp [ 2375 ]);

    # ============================================================
    # Stack Directory Structure
    # ============================================================
    systemd.tmpfiles.rules = [
      "d /opt/stacks/${cfg.stackName} 0755 root root -"
      "d /opt/stacks/${cfg.stackName}/config 0755 root root -"
    ];

    # ============================================================
    # Deploy compose.yml
    # ============================================================
    # Copy compose file to /etc, then symlink to /opt/stacks
    # This ensures the file is managed by NixOS and survives rebuilds
    environment.etc."stacks/${cfg.stackName}/compose.yml".source = cfg.composeFile;

    # Symlink from /opt/stacks for docker-compose working directory
    # The .env file will be placed here by Colmena keys
    systemd.services."${cfg.stackName}-link-compose" = {
      description = "Symlink compose.yml to stack directory";
      wantedBy = [ "multi-user.target" ];
      before = [ "${cfg.stackName}-stack.service" ];
      after = [ "local-fs.target" ];

      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        ExecStart = "${pkgs.coreutils}/bin/ln -sf /etc/stacks/${cfg.stackName}/compose.yml /opt/stacks/${cfg.stackName}/compose.yml";
      };
    };

    # ============================================================
    # Docker Compose Systemd Service
    # ============================================================
    systemd.services."${cfg.stackName}-stack" = {
      description = "${cfg.stackName} Docker Compose Stack";
      after = [
        "docker.service"
        "network-online.target"
        "${cfg.stackName}-link-compose.service"
        "stack-restore.service" # Wait for NFS restore if enabled
      ];
      wants = [ "network-online.target" ];
      wantedBy = [ "multi-user.target" ];

      path = [ pkgs.docker pkgs.docker-compose ];

      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        WorkingDirectory = "/opt/stacks/${cfg.stackName}";
        ExecStart = "${pkgs.docker-compose}/bin/docker-compose up -d --remove-orphans";
        ExecStop = "${pkgs.docker-compose}/bin/docker-compose down";
        Restart = "on-failure";
        RestartSec = "10s";
      };
    };
  };
}
