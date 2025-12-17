# Homelab

Infrastructure-as-code for deploying Docker hosts on Proxmox using OpenTofu.

## Prerequisites

- [OpenTofu](https://opentofu.org/) or Terraform
- [1Password CLI](https://developer.1password.com/docs/cli/) (`op`)
- [direnv](https://direnv.net/)
- SSH key at `~/.ssh/id_ed25519.pub`

## Quick Start

```bash
# Copy and customize environment config
cp .env.example .env
# Edit .env to match your Proxmox setup (node name, storage, etc.)

# Allow direnv to load environment (loads .env and resolves op:// refs)
direnv allow

# Initialize and deploy
cd infrastructure
tofu init
tofu plan
tofu apply
```

## Structure

```
homelab/
├── .env.example          # Environment config template (op:// refs)
├── .envrc                # Direnv config (loads .env, resolves 1Password)
├── infrastructure/       # OpenTofu configuration
│   ├── templates/        # Cloud-init and NixOS templates
│   ├── main.tf           # VM definitions
│   └── secrets.tf        # 1Password integration
└── stacks/               # Docker Compose stacks
    ├── arr/              # Media automation (Sonarr, Radarr, etc.)
    └── netbird/          # Self-hosted VPN
```

## 1Password Setup

Create these items in your "Infrastructure" vault:

1. **Proxmox** - Login item with:
   - `url`: Proxmox API URL (e.g., `https://proxmox.local:8006/api2/json`)
   - `token_id`: API token ID (e.g., `tofu@pve!tofu-token`)
   - `credential`: API token secret

2. **env-arr-stack** - Secure Note containing the full `.env` content for the arr stack
