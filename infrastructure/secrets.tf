# =============================================================================
# 1PASSWORD SECRETS
# =============================================================================
# Fetch stack secrets from 1Password at apply time.
# Requires: OP_SERVICE_ACCOUNT_TOKEN environment variable
#
# To set up in 1Password:
# 1. Create a "Secure Note" item named "env-<stack>-stack" in your vault
# 2. Put the entire .env content in the "notes" field
#
# For NixOS VMs: Secrets are deployed by Colmena using `deployment.keys`
# For Ubuntu VMs: Secrets are embedded in cloud-init at provision time

# ---------------------------------------------------------------------------
# Ubuntu VM Secrets (embedded in cloud-init)
# ---------------------------------------------------------------------------

# Fetch portainer stack secrets
data "onepassword_item" "portainer_stack" {
  vault = var.onepassword_vault
  title = "env-portainer-stack"
}

# Map of stack name to env content (for Ubuntu VMs only)
locals {
  stack_env_content = {
    # Use note_value for Secure Note items containing full .env
    portainer = data.onepassword_item.portainer_stack.note_value
  }
}

# ---------------------------------------------------------------------------
# Note: NixOS VM secrets are managed by Colmena
# ---------------------------------------------------------------------------
# NixOS VMs (arr, tools) get their secrets via Colmena's deployment.keys
# which runs `op read op://Infrastructure/env-<stack>-stack/notesPlain`
# at deploy time. This keeps secrets out of the Nix store.
#
# To create a new secret for NixOS:
#   op item create --category="Secure Note" --title="env-<stack>-stack" \
#     --vault="Infrastructure" 'notesPlain=KEY1=value1
# KEY2=value2'
