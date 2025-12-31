# Base NixOS image for Proxmox VMs
# Built with nixos-generators, creates a VMA file
#
# Build: nix build .#proxmox-image
# Output: result/nixos.vma.zst
{ config, pkgs, lib, modulesPath, sshKeys, ... }:

{
  imports = [
    "${modulesPath}/profiles/qemu-guest.nix"
  ];

  system.stateVersion = "25.05";

  # ============================================================
  # Boot Configuration
  # ============================================================
  boot.loader.grub = {
    enable = true;
    device = "/dev/vda";
  };

  boot.growPartition = true;

  # Kernel params for serial console (Proxmox xterm.js)
  boot.kernelParams = [ "console=ttyS0,115200" "console=tty0" ];

  # ============================================================
  # Proxmox Integration
  # ============================================================
  services.qemuGuest.enable = true;

  # ============================================================
  # SSH Configuration
  # ============================================================
  services.openssh = {
    enable = true;
    settings = {
      PermitRootLogin = "prohibit-password";
      PasswordAuthentication = false;
    };
  };

  # Bake SSH keys into image for initial access
  users.users.root.openssh.authorizedKeys.keys = sshKeys;

  # ============================================================
  # Docker (pre-installed)
  # ============================================================
  virtualisation.docker = {
    enable = true;
    autoPrune = {
      enable = true;
      dates = "weekly";
    };
  };

  # ============================================================
  # Base Packages
  # ============================================================
  environment.systemPackages = with pkgs; [
    vim
    git
    curl
    wget
    htop
    jq
    rsync
    nfs-utils
    docker-compose
  ];

  # ============================================================
  # Networking Defaults
  # ============================================================
  # Disable predictable interface naming (use eth0 instead of ens18)
  networking.usePredictableInterfaceNames = false;

  # Static IP for initial boot - Colmena will override per-host
  networking.useDHCP = false;
  networking.interfaces.eth0.ipv4.addresses = lib.mkDefault [{
    address = "10.0.0.199";
    prefixLength = 24;
  }];
  networking.defaultGateway = lib.mkDefault "10.0.0.1";
  networking.nameservers = lib.mkDefault [ "10.0.0.1" ];

  # Base firewall - hosts will add their own ports
  networking.firewall = {
    enable = true;
    allowedTCPPorts = [ 22 ];
  };

  # ============================================================
  # Filesystem
  # ============================================================
  # Root filesystem - nixos-generators handles partitioning
  # We just ensure the root fs can auto-resize
  fileSystems."/" = lib.mkDefault {
    device = "/dev/vda1";
    fsType = "ext4";
    autoResize = true;
  };

  # Ensure stack directories exist
  systemd.tmpfiles.rules = [
    "d /opt/stacks 0755 root root -"
    "d /mnt/nfs-backup 0755 root root -"
  ];
}
