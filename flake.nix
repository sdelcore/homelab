{
  description = "Homelab infrastructure development environment";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.11";
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

          # Task runner
          just

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
          echo "Run 'just' to see available commands"
          echo ""
        '';
      };
    };
}
