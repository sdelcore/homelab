{
  description = "Homelab infrastructure development environment";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.05";
    colmena.url = "github:zhaofengli/colmena";
  };

  outputs = { self, nixpkgs, colmena }:
    let
      system = "x86_64-linux";
      pkgs = import nixpkgs {
        inherit system;
        config.allowUnfree = true; # For 1password-cli
      };
    in
    {
      devShells.${system}.default = pkgs.mkShell {
        packages = with pkgs; [
          # Infrastructure provisioning
          opentofu

          # NixOS deployment
          colmena.packages.${system}.colmena
          nixos-anywhere

          # Utilities
          jq
          zstd # For decompressing VMA images

          # 1Password CLI for secrets
          _1password-cli
        ];

        shellHook = ''
          echo ""
          echo "=== Homelab Development Environment ==="
          echo ""
          echo "Deployment commands:"
          echo "  ./scripts/deploy.sh              Full deployment (image + tofu + colmena)"
          echo "  ./scripts/deploy.sh --colmena-only   Deploy NixOS configs only"
          echo "  ./scripts/upload-nixos-image.sh  Build and upload NixOS image"
          echo ""
          echo "Individual tools:"
          echo "  colmena apply                    Deploy NixOS configurations"
          echo "  colmena apply --on arr           Deploy to specific host"
          echo "  colmena build                    Build without deploying"
          echo "  tofu apply                       Provision VMs"
          echo ""
          echo "NixOS image:"
          echo "  cd nixos && nix build .#proxmox-image"
          echo ""
        '';
      };
    };
}
