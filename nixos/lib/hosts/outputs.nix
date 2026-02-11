# Generate all flake outputs from validated hosts
#
# Produces nixosConfigurations, colmenaHive, and terraformHosts
# from the validated host definitions.
{ lib, nixpkgs, system, pkgs, colmena, sshKeys, nfsConfig, networkConfig
, sharedModules, validatedHosts, hostsDir, mkHostConfig }:

let
  # ============================================================
  # NixOS Configurations (for nixos-anywhere)
  # ============================================================
  # Install: nixos-anywhere --flake .#<hostname> root@<ip>
  nixosConfigurations = builtins.mapAttrs (name: host:
    nixpkgs.lib.nixosSystem {
      inherit system;
      specialArgs = {
        inherit name sshKeys nfsConfig;
      };
      modules = sharedModules ++ [
        (mkHostConfig name host)
        (hostsDir + "/${name}.nix")
        { nixpkgs.config.allowUnfree = true; }
      ];
    }
  ) validatedHosts;

  # ============================================================
  # Colmena Deployment
  # ============================================================
  # Deploy: colmena apply
  # Deploy single: colmena apply --on arr
  colmenaHive = colmena.lib.makeHive ({
    meta = {
      nixpkgs = pkgs;
      specialArgs = {
        inherit sshKeys nfsConfig;
      };
    };

    # Default configuration applied to all hosts
    defaults = { name, ... }:
    let
      host = validatedHosts.${name};
    in
    {
      imports = sharedModules ++ [ (mkHostConfig name host) ];

      # ============================================================
      # Colmena Deployment Settings
      # ============================================================
      deployment = {
        targetHost = host.ip;
        targetUser = "root";
        tags = host.tags;

        # Password hashes from 1Password (for console and SSH login)
        keys = {
          "sdelcore-password" = {
            keyCommand = [ "op" "read" "op://Infrastructure/sdelcore/password" ];
            user = "root";
            group = "root";
            permissions = "0600";
          };
          "root-password" = {
            keyCommand = [ "op" "read" "op://Infrastructure/sdelcore/password" ];
            user = "root";
            group = "root";
            permissions = "0600";
          };

          # Secret: .env file from 1Password
          "stack-env" = {
            keyCommand = [ "op" "read" "op://Infrastructure/env-${name}-stack/notesPlain" ];
            destDir = "/opt/stacks/${name}";
            name = ".env";
            user = "root";
            group = "root";
            permissions = "0600";
          };
        };
      };
    };

    # Host-specific configurations (auto-registered from validated hosts)
  } // builtins.mapAttrs (name: _: import (hostsDir + "/${name}.nix")) validatedHosts);

  # ============================================================
  # Terraform/OpenTofu Host Data
  # ============================================================
  terraformHosts = {
    network = networkConfig;
    nfs = nfsConfig;
    hosts = lib.mapAttrs (name: host: {
      inherit (host) ip mac node vmId cores memory disk domain tags;
      gpu = host.gpu or false;
    } // lib.optionalAttrs (host ? gpuId) {
      inherit (host) gpuId;
    }) validatedHosts;
  };

in {
  inherit nixosConfigurations colmenaHive terraformHosts;
}
