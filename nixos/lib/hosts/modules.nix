# Host validation and module assembly
#
# Validates host attribute sets and assembles NixOS module lists
# for each host configuration.
{ lib, networkConfig, stacksPath }:

let
  requiredAttrs = [ "ip" "mac" "node" "vmId" "cores" "memory" "disk" "domain" "tags" ];

  # ============================================================
  # Validate a host definition has all required attributes
  # ============================================================
  validateHost = name: host:
    let
      missing = builtins.filter (attr: !(host ? ${attr})) requiredAttrs;
    in
    if missing == [] then host
    else builtins.throw "Host '${name}' is missing required attributes: ${builtins.concatStringsSep ", " missing}";

  # ============================================================
  # Per-host configuration derived from host attrset
  # ============================================================
  mkHostConfig = name: host: { ... }: {
    # ============================================================
    # Network Configuration
    # ============================================================
    networking.hostName = name;
    networking.useDHCP = false;
    networking.interfaces.eth0.ipv4.addresses = [{
      address = host.ip;
      prefixLength = networkConfig.prefixLength;
    }];
    networking.defaultGateway = networkConfig.gateway;
    networking.nameservers = networkConfig.nameservers;

    # ============================================================
    # Docker Stack
    # ============================================================
    dockerStack = {
      enable = true;
      stackName = name;
      composeFile = stacksPath + "/${name}/compose.yml";
    };

    # ============================================================
    # NFS Backup
    # ============================================================
    nfsBackup = {
      enable = true;
      stackName = name;
    };

    # ============================================================
    # NVIDIA GPU Support
    # ============================================================
    nvidia.enable = host.gpu or false;

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

in {
  inherit validateHost mkHostConfig;
}
