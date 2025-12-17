# Stacks Directory

This directory contains copies of the compose files from `../stacks/` for use
with Colmena deployment. Nix flakes require all referenced files to be within
the flake directory.

## Keeping Files in Sync

When you update a compose file in `stacks/`, copy it here as well:

```bash
cp ../stacks/arr/compose.yml stacks/arr/
cp ../stacks/tools/compose.yml stacks/tools/
```

Or use the sync script:

```bash
./sync-stacks.sh
```
