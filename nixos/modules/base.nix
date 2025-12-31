# Common configuration for all NixOS hosts
{ config, pkgs, lib, sshKeys, ... }:

{
  # ============================================================
  # System
  # ============================================================
  system.stateVersion = "25.05";

  # ============================================================
  # Time and Locale
  # ============================================================
  time.timeZone = "America/Toronto";
  i18n.defaultLocale = "en_CA.UTF-8";

  # ============================================================
  # User Configuration
  # ============================================================
  users.users.sdelcore = {
    isNormalUser = true;
    extraGroups = [ "wheel" "docker" ];
    openssh.authorizedKeys.keys = sshKeys;
    shell = pkgs.zsh;
    hashedPasswordFile = "/run/keys/sdelcore-password";
  };

  # Enable zsh system-wide (required for user shell)
  programs.zsh.enable = true;

  users.users.root = {
    openssh.authorizedKeys.keys = sshKeys;
    hashedPasswordFile = "/run/keys/root-password";
  };

  security.sudo.wheelNeedsPassword = false;

  # ============================================================
  # SSH
  # ============================================================
  services.openssh = {
    enable = true;
    settings = {
      PermitRootLogin = "yes";
      PasswordAuthentication = true;
    };
  };

  # ============================================================
  # QEMU Guest Agent
  # ============================================================
  services.qemuGuest.enable = true;

  # ============================================================
  # Boot Configuration
  # ============================================================
  boot.loader.grub = {
    enable = true;
    device = "/dev/vda";
  };

  # Kernel params for serial console (Proxmox xterm.js)
  boot.kernelParams = [ "console=ttyS0,115200" "console=tty0" ];

  # Include virtio modules in initrd for Proxmox VMs
  # Required because qemu-guest profile is only in image.nix, not Colmena config
  boot.initrd.availableKernelModules = [
    "virtio_pci"
    "virtio_blk"
    "virtio_scsi"
    "virtio_net"
  ];

  # ============================================================
  # Filesystem (required for NixOS)
  # ============================================================
  # Root filesystem on virtio disk (matches nixos-generators proxmox format)
  fileSystems."/" = {
    device = "/dev/vda1";
    fsType = "ext4";
  };

  # ============================================================
  # Common Packages
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
  # Base Firewall
  # ============================================================
  networking.firewall = {
    enable = true;
    allowedTCPPorts = [ 22 ];
  };
}
