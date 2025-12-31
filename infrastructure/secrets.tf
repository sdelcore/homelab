# =============================================================================
# 1PASSWORD SECRETS
# =============================================================================
# NixOS VM secrets are managed by Colmena, not OpenTofu.
#
# Colmena's deployment.keys runs `op read op://Infrastructure/env-<stack>-stack/notesPlain`
# at deploy time. This keeps secrets out of the Nix store.
#
# To create a new secret for a NixOS VM:
#   op item create --category="Secure Note" --title="env-<stack>-stack" \
#     --vault="Infrastructure" 'notesPlain=KEY1=value1
# KEY2=value2'
#
# Ubuntu VM templates are kept in templates/ for reference but are not deployed.
# =============================================================================
