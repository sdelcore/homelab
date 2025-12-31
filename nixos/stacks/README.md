# Docker Compose Stacks

This directory contains Docker Compose stacks deployed to NixOS VMs via Colmena.

## Stacks

| Stack | VM | Description |
|-------|-----|-------------|
| arr | arr | Media automation (Sonarr, Radarr, Deluge, etc.) |
| tools | tools | Infrastructure tools (Homepage, Traefik) |
| aria | aria | Aria2 download manager |
| nvr | nvr | Frigate NVR with GPU passthrough |

## Directory Structure

Each stack directory contains:
- `compose.yml` - Docker Compose configuration
- `config/` - Application configuration files (optional)
- `.env.example` - Example environment variables (optional)

## Adding a New Stack

1. Create directory: `nixos/stacks/<name>/`
2. Add `compose.yml` and any config files
3. Create NixOS host config: `nixos/hosts/<name>.nix`
4. Register host in `nixos/flake.nix` colmenaHive
5. Add VM definition to `infrastructure/main.tf`
6. Create 1Password secret:
   ```bash
   op item create --category="Secure Note" --title="env-<name>-stack" \
     --vault="Infrastructure" 'notesPlain=KEY1=value1
   KEY2=value2'
   ```
7. Deploy: `tofu apply && colmena apply --on <name>`
