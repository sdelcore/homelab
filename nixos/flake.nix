{
  description = "NixOS homelab - Proxmox VMs managed by Colmena";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.05";

    nixos-generators = {
      url = "github:nix-community/nixos-generators";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    colmena = {
      url = "github:zhaofengli/colmena";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Home-manager for user environment configuration
    home-manager = {
      url = "github:nix-community/home-manager/release-25.05";
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

  outputs = { self, nixpkgs, nixos-generators, colmena, home-manager, catppuccin, sdelcore-nixos, ... }:
    let
      system = "x86_64-linux";
      pkgs = import nixpkgs {
        inherit system;
        config.allowUnfree = true;  # For NVIDIA drivers
      };

      # ============================================================
      # Load shared configuration from hosts.json
      # ============================================================
      # Note: hosts.json is symlinked from repo root to nixos/ for flake access
      hostsConfig = builtins.fromJSON (builtins.readFile ./hosts.json);

      # Shared SSH keys for all hosts
      sshKeys = [
        "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAACAQDbCTR4sfbJyTfM/jYhVXZsPMU2QoEib0usUVtmIjU+tjohaZZ8X6maMT32y7V5Ii91TiOxILkh+jd3nbc5svO27li4bjz704Mm6IfNuetv0+YbsfjngLk/VcNBpUbJskEoCh+oiq5JCo9wXmmNZEGaq4LM/FKsnRnTiGlnjeJ9d892sps2eRnjDKLRtO1K+k7C/+UmIOp7qU1CPD7wFys7arIM6m+DdDnNR47syLFJaQA3TxCw01+zG0hNNAMFU1g5Ck41mVQYXAIl5fjGbM+C6jNSl0f64TcZv8+G28uN/uvt/cJYwEH1jC640ieRrStVeYBiUlUuco4Eb1SVIabVNkb2je9wI1qw2VoDjXq+bQFlBHzMj4mPESNVRmrfEg0+KXFvYKvKcOMlYsSfAtLujKa6/4z3Ai3eQQlwo4mZdULe8AY1pbJ4Hb2o/NF8zumsXDci2pYUMzNmWOSonuS+MYIvNEMY5H3sBMC9jkLfvNbm5AA6jadAr/Jkb3Lu168ip8QTQAz/pIecyXQKWXN9bwgMvU3ZxSaHOWL0loeRUiBdAmqJQEQgh7ANZoLIL3uqtaYPPT0pBMMm3V4fEESJ6uWq+lZNFs1DqehMWaBRZ1u86qLZqx8kf46dQB+oW2mWtU2/Re4Ur0cBWR/L2VimwmlB2epsRJT1Lz0kA+jnUw=="
      ];

      # NFS config from hosts.json
      nfsConfig = hostsConfig.nfs;

      # Network config from hosts.json
      networkConfig = hostsConfig.network;

      # Path to stacks directory
      stacksPath = ./stacks;

    in
    {
      # ============================================================
      # Proxmox VMA Image
      # ============================================================
      # Build: nix build .#proxmox-image
      # Output: result/nixos.vma.zst
      packages.${system} = {
        proxmox-image = nixos-generators.nixosGenerate {
          inherit system;
          format = "proxmox";
          modules = [
            ./image.nix
            {
              _module.args = { inherit sshKeys; };
            }
          ];
        };

        # Convenience alias
        default = self.packages.${system}.proxmox-image;
      };

      # ============================================================
      # Colmena Deployment
      # ============================================================
      # Deploy: colmena apply
      # Deploy single: colmena apply --on arr
      colmenaHive = colmena.lib.makeHive {
        meta = {
          nixpkgs = pkgs;
          specialArgs = {
            inherit sshKeys nfsConfig networkConfig stacksPath hostsConfig;
          };
        };

        # Default configuration applied to all hosts
        defaults = { pkgs, lib, ... }: {
          imports = [
            ./modules/base.nix
            ./modules/docker-stack.nix
            ./modules/nfs-backup.nix
            ./modules/nvidia.nix
            home-manager.nixosModules.home-manager
          ];

          # Password hashes from 1Password (for console and SSH login)
          deployment.keys = {
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
          };

          # Home-manager configuration for sdelcore user
          home-manager = {
            useGlobalPkgs = true;
            useUserPackages = true;
            backupFileExtension = "backup";

            sharedModules = [ ];

            users.sdelcore = { pkgs, ... }: {
              home.username = "sdelcore";
              home.homeDirectory = "/home/sdelcore";
              home.stateVersion = "25.05";

              # Basic packages for headless use
              home.packages = with pkgs; [
                htop
                ripgrep
                fd
                jq
                tree
              ];

              # Basic shell config
              programs.bash.enable = true;
              programs.git.enable = true;
            };
          };
        };

        # Host-specific configurations
        arr = import ./hosts/arr.nix;
        tools = import ./hosts/tools.nix;
        nvr = import ./hosts/nvr.nix;
        aria = import ./hosts/aria.nix;
      };
    };
}
