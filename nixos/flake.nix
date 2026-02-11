{
  description = "NixOS homelab - Proxmox VMs managed by Colmena";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.11";

    disko = {
      url = "github:nix-community/disko";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    colmena = {
      url = "github:zhaofengli/colmena";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Home-manager for user environment configuration
    home-manager = {
      url = "github:nix-community/home-manager/release-25.11";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Catppuccin theming
    catppuccin.url = "github:catppuccin/nix";

    # Personal NixOS config (for headless home-manager modules)
    sdelcore-nixos = {
      url = "github:sdelcore/nixos";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { self, nixpkgs, disko, colmena, home-manager, catppuccin, sdelcore-nixos, ... }:
    let
      system = "x86_64-linux";
      pkgs = import nixpkgs {
        inherit system;
        config.allowUnfree = true;  # For NVIDIA drivers
      };
      lib = nixpkgs.lib;

      # ============================================================
      # SSH Keys
      # ============================================================
      sshKeys = [
        "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAILt/+MqQJoCw5xNAyqBM8taSJAwb+nTuTQXEHx/yGCRs"
        "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAACAQDbCTR4sfbJyTfM/jYhVXZsPMU2QoEib0usUVtmIjU+tjohaZZ8X6maMT32y7V5Ii91TiOxILkh+jd3nbc5svO27li4bjz704Mm6IfNuetv0+YbsfjngLk/VcNBpUbJskEoCh+oiq5JCo9wXmmNZEGaq4LM/FKsnRnTiGlnjeJ9d892sps2eRnjDKLRtO1K+k7C/+UmIOp7qU1CPD7wFys7arIM6m+DdDnNR47syLFJaQA3TxCw01+zG0hNNAMFU1g5Ck41mVQYXAIl5fjGbM+C6jNSl0f64TcZv8+G28uN/uvt/cJYwEH1jC640ieRrStVeYBiUlUuco4Eb1SVIabVNkb2je9wI1qw2VoDjXq+bQFlBHzMj4mPESNVRmrfEg0+KXFvYKvKcOMlYsSfAtLujKa6/4z3Ai3eQQlwo4mZdULe8AY1pbJ4Hb2o/NF8zumsXDci2pYUMzNmWOSonuS+MYIvNEMY5H3sBMC9jkLfvNbm5AA6jadAr/Jkb3Lu168ip8QTQAz/pIecyXQKWXN9bwgMvU3ZxSaHOWL0loeRUiBdAmqJQEQgh7ANZoLIL3uqtaYPPT0pBMMm3V4fEESJ6uWq+lZNFs1DqehMWaBRZ1u86qLZqx8kf46dQB+oW2mWtU2/Re4Ur0cBWR/L2VimwmlB2epsRJT1Lz0kA+jnUw=="
      ];

      # ============================================================
      # Network Configuration
      # ============================================================
      networkConfig = {
        gateway = "10.0.0.1";
        prefixLength = 24;
        nameservers = [ "10.0.0.1" "1.1.1.1" "8.8.8.8" ];
      };

      # ============================================================
      # NFS Configuration
      # ============================================================
      nfsConfig = {
        server = "10.0.0.5";
        export = "/mnt/user/infrastructure";
        backupSubdir = "docker-data/backups";
      };

      # Path to stacks directory
      stacksPath = ./stacks;

      # ============================================================
      # Host Definitions (single source of truth)
      # ============================================================
      hosts = {
        arr = {
          ip = "10.0.0.20";
          mac = "BC:24:11:00:00:14";
          node = "strongmad";
          vmId = 200;
          cores = 4;
          memory = 2048;
          disk = 50;
          domain = "arr.tap";
          tags = [ "docker" "media" "nixos" ];
          gpu = false;
        };
        tools = {
          ip = "10.0.0.21";
          mac = "BC:24:11:00:00:15";
          node = "strongmad";
          vmId = 201;
          cores = 2;
          memory = 2048;
          disk = 30;
          domain = "tools.tap";
          tags = [ "docker" "tools" "nixos" ];
          gpu = false;
        };
        aria = {
          ip = "10.0.0.23";
          mac = "BC:24:11:00:00:17";
          node = "strongmad";
          vmId = 204;
          cores = 2;
          memory = 2048;
          disk = 20;
          domain = "aria.tap";
          tags = [ "docker" "aria" "mem" "nixos" ];
          gpu = false;
        };
        nvr = {
          ip = "10.0.0.16";
          mac = "BC:24:11:00:00:10";
          node = "strongbad";
          vmId = 203;
          cores = 4;
          memory = 4096;
          disk = 50;
          domain = "nvr.tap";
          tags = [ "docker" "nvr" "nvidia" "nixos" ];
          gpu = true;
          gpuId = "0000:04:00.0";
        };
        media = {
          ip = "10.0.0.15";
          mac = "BC:24:11:00:00:18";
          node = "strongbad";
          vmId = 205;
          cores = 4;
          memory = 8192;
          disk = 50;
          domain = "media.tap";
          tags = [ "docker" "media" "nvidia" "nixos" ];
          gpu = true;
          gpuId = "0000:01:00.0";
        };
      };

    in
    import ./lib/hosts.nix {
      inherit lib nixpkgs system pkgs colmena disko home-manager
              hosts sshKeys networkConfig nfsConfig stacksPath;
    } // { inherit hosts; };
}
