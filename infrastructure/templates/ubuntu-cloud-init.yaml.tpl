#cloud-config
hostname: ${hostname}
timezone: ${timezone}
manage_etc_hosts: true
ssh_pwauth: true

users:
  - default
  - name: ${username}
    groups: [adm, sudo, docker]
    shell: /bin/bash
    sudo: ALL=(ALL) NOPASSWD:ALL
    lock_passwd: false
    # Password: asd (SHA-512 hash)
    passwd: $6$8whPC7sgv6AutgiJ$6N3K4pytSAk39ijeiDSJ/.uYfP7Fj2c/gsv7k/DEP.xHQWkt0QZXmuJml5sY.n2hRtaEqJVWQI5m4jggXbICs.
    ssh_authorized_keys:%{ for key in ssh_keys }
      - ${key}%{ endfor }

package_update: true
package_upgrade: true

packages:
  - qemu-guest-agent
  - curl
  - wget
  - vim
  - htop
  - net-tools
  - ca-certificates
  - gnupg
  - python3
  - python3-pip
  - nfs-common
  - rsync
  - git

write_files:
  # Stack environment file (from 1Password)
  # Note: owner set via chown in runcmd (write_files runs before user creation)
  - path: /opt/stacks/${stack}/.env
    permissions: '0600'
    content: |
      ${replace(env_content, "\n", "\n      ")}

  # Stack compose file
  - path: /opt/stacks/${stack}/compose.yml
    permissions: '0644'
    content: |
      ${replace(compose_content, "\n", "\n      ")}

  # Docker installation script
  - path: /opt/stacks/install-docker.sh
    permissions: '0755'
    content: |
      ${replace(install_docker_script, "\n", "\n      ")}

  # NFS backup restoration script
  - path: /opt/stacks/restore-nfs-backup.sh
    permissions: '0755'
    content: |
      ${replace(restore_nfs_script, "\n", "\n      ")}

  # NFS backup script
  - path: /opt/stacks/backup-to-nfs.sh
    permissions: '0755'
    content: |
      ${replace(backup_nfs_script, "\n", "\n      ")}
%{ if enable_home_manager ~}

  # Home-manager deployment script
  # Note: owner set via chown in runcmd (write_files runs before user creation)
  - path: /opt/scripts/deploy-home-manager.sh
    permissions: '0755'
    content: |
      #!/usr/bin/env bash
      set -euo pipefail

      FLAKE_REPO="${nixos_flake_repo}"
      USERNAME="${username}"
      FLAKE_DIR="$HOME/.config/nixos"

      echo "==> Deploying home-manager for $USERNAME"

      # Clone or update flake repo
      if [ -d "$FLAKE_DIR" ]; then
        echo "==> Updating existing flake repo..."
        git -C "$FLAKE_DIR" pull --rebase
      else
        echo "==> Cloning flake repo..."
        git clone "$FLAKE_REPO" "$FLAKE_DIR"
      fi

      # Run home-manager switch
      echo "==> Running home-manager switch..."
      nix run home-manager/release-25.05 -- switch --flake "$FLAKE_DIR#headless" -b backup

      echo "==> Home-manager deployment complete!"
      echo "==> Run 'exec zsh' or log out and back in to use new shell"
%{ endif ~}

  # Systemd service for hourly backups
  - path: /etc/systemd/system/stack-backup.service
    permissions: '0644'
    content: |
      [Unit]
      Description=Backup Docker stack configs to NFS

      [Service]
      Type=oneshot
      ExecStart=/opt/stacks/backup-to-nfs.sh

  # Systemd timer for hourly backups
  - path: /etc/systemd/system/stack-backup.timer
    permissions: '0644'
    content: |
      [Unit]
      Description=Hourly backup of Docker stack configs

      [Timer]
      OnCalendar=hourly
      Persistent=true

      [Install]
      WantedBy=timers.target

  # Systemd service for the Docker stack
  - path: /etc/systemd/system/${stack}-stack.service
    permissions: '0644'
    content: |
      [Unit]
      Description=${stack} Docker Compose Stack
      Requires=docker.service
      After=docker.service network-online.target

      [Service]
      Type=oneshot
      RemainAfterExit=yes
      WorkingDirectory=/opt/stacks/${stack}
      ExecStart=/usr/bin/docker compose up -d --remove-orphans
      ExecStop=/usr/bin/docker compose down

      [Install]
      WantedBy=multi-user.target
%{ if enable_docker_tcp ~}

  # Docker daemon config for TCP socket (Homepage discovery)
  - path: /etc/docker/daemon.json
    permissions: '0644'
    content: |
      {
        "hosts": ["unix:///var/run/docker.sock", "tcp://0.0.0.0:2375"]
      }

  # Override Docker service to not use -H flag (conflicts with daemon.json)
  - path: /etc/systemd/system/docker.service.d/override.conf
    permissions: '0644'
    content: |
      [Service]
      ExecStart=
      ExecStart=/usr/bin/dockerd --containerd=/run/containerd/containerd.sock
%{ endif ~}

runcmd:
  - systemctl enable --now qemu-guest-agent
%{ if enable_home_manager ~}

  # Install Nix (Determinate Systems installer - multi-user)
  - curl --proto '=https' --tlsv1.2 -sSf -L https://install.determinate.systems/nix | sh -s -- install --no-confirm
  - mkdir -p /opt/scripts
  - chown -R ${username}:${username} /opt/scripts

  # Run home-manager deployment as user
  - su - ${username} -c '/opt/scripts/deploy-home-manager.sh'

  # Ensure zsh can find nix (zsh doesn't read /etc/profile.d/, only bash does)
  - echo 'source /etc/profile.d/nix.sh' > /etc/zshenv

  # Set nix-managed zsh as default shell (must be in /etc/shells for chsh)
  - echo '/home/${username}/.nix-profile/bin/zsh' >> /etc/shells
  - chsh -s /home/${username}/.nix-profile/bin/zsh ${username}
%{ endif ~}

  # Install Docker
  - /opt/stacks/install-docker.sh

  # Setup stack directory
  - mkdir -p /opt/stacks/${stack}/config
  - chown -R ${username}:${username} /opt/stacks

  # Restore config from NFS backup if exists
  - /opt/stacks/restore-nfs-backup.sh
  - chown -R ${username}:${username} /opt/stacks/${stack}

  # Enable systemd services
  - systemctl daemon-reload
  - systemctl enable --now stack-backup.timer
  - systemctl enable ${stack}-stack.service

  # Start the stack
  - cd /opt/stacks/${stack} && docker compose up -d || echo "Stack failed to start - check configuration"

  - touch /var/lib/cloud/instance/boot-finished

final_message: "Cloud-init completed after $UPTIME seconds"
