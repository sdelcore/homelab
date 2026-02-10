# Declarative disk partitioning for all Proxmox VMs
# GPT partition table with BIOS boot partition + ext4 root on /dev/vda
# Used by nixos-anywhere for initial installation and disko for ongoing management
{ ... }:
{
  disko.devices.disk.vda = {
    type = "disk";
    device = "/dev/vda";
    content = {
      type = "gpt";
      partitions = {
        boot = {
          size = "1M";
          type = "EF02"; # BIOS boot partition for GPT+GRUB
        };
        root = {
          size = "100%";
          content = {
            type = "filesystem";
            format = "ext4";
            mountpoint = "/";
          };
        };
      };
    };
  };
}
