# NVIDIA GPU support module for Docker containers
#
# Enables NVIDIA drivers and container toolkit for GPU passthrough VMs.
# Uses CDI (Container Device Interface) for Docker GPU access.
{ config, pkgs, lib, ... }:

with lib;

let
  cfg = config.nvidia;
in
{
  options.nvidia = {
    enable = mkEnableOption "NVIDIA GPU support with container toolkit";
  };

  config = mkIf cfg.enable {
    # ============================================================
    # NVIDIA Driver Configuration
    # ============================================================
    # Enable graphics support
    hardware.graphics.enable = true;

    # Use NVIDIA proprietary drivers (T400 is Turing architecture)
    services.xserver.videoDrivers = [ "nvidia" ];

    hardware.nvidia = {
      # Use proprietary drivers (more stable for Turing GPUs)
      open = false;

      # Disable modesetting for headless/compute-only use
      # This prevents framebuffer initialization which hangs with vga: none
      modesetting.enable = false;

      # Power management (not needed for always-on server VMs)
      powerManagement.enable = false;

      # Use production driver branch
      package = config.boot.kernelPackages.nvidiaPackages.production;
    };

    # ============================================================
    # Container Toolkit (CDI method)
    # ============================================================
    # Enables Docker containers to access GPU via CDI device spec:
    #   devices:
    #     - driver: cdi
    #       device_ids:
    #         - nvidia.com/gpu=all
    hardware.nvidia-container-toolkit.enable = true;

    # ============================================================
    # Useful packages for GPU monitoring
    # ============================================================
    environment.systemPackages = with pkgs; [
      nvtopPackages.nvidia # GPU monitoring tool
    ];
  };
}
