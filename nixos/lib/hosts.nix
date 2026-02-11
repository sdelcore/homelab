# Host wiring entry point
#
# Defines shared NixOS modules, validates host definitions,
# and delegates to outputs.nix for flake output generation.
{ lib, nixpkgs, system, pkgs, colmena, disko, home-manager
, hosts, sshKeys, networkConfig, nfsConfig, stacksPath }:

let
  # ============================================================
  # Shared NixOS modules (used by both nixosConfigurations and Colmena)
  # ============================================================
  sharedModules = [
    disko.nixosModules.disko
    ../modules/disko.nix
    ../modules/base.nix
    ../modules/docker-stack.nix
    ../modules/nfs-backup.nix
    ../modules/nvidia.nix
    home-manager.nixosModules.home-manager
  ];

  hostsDir = ../hosts;

  # ============================================================
  # Import host validation and module assembly
  # ============================================================
  modules = import ./hosts/modules.nix {
    inherit lib networkConfig stacksPath;
  };
  inherit (modules) validateHost mkHostConfig;

  # Validate all host definitions
  validatedHosts = lib.mapAttrs validateHost hosts;

in
  # ============================================================
  # Generate all flake outputs
  # ============================================================
  import ./hosts/outputs.nix {
    inherit lib nixpkgs system pkgs colmena sshKeys nfsConfig networkConfig
            sharedModules validatedHosts hostsDir mkHostConfig;
  }
