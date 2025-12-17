#cloud-config
# Minimal cloud-init for NixOS bootstrap via nixos-anywhere
# This just sets up SSH access - nixos-anywhere will handle the rest

users:
  - name: root
    ssh_authorized_keys:
%{ for key in ssh_keys ~}
      - ${key}
%{ endfor ~}

# Ensure SSH is running
runcmd:
  - systemctl enable --now ssh || systemctl enable --now sshd
