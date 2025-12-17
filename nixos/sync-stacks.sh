#!/usr/bin/env bash
# Sync compose files from ../stacks to nixos/stacks
# Run this after updating compose files

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

echo "Syncing compose files..."

mkdir -p "$SCRIPT_DIR/stacks/arr" "$SCRIPT_DIR/stacks/tools"

cp "$PROJECT_ROOT/stacks/arr/compose.yml" "$SCRIPT_DIR/stacks/arr/"
cp "$PROJECT_ROOT/stacks/tools/compose.yml" "$SCRIPT_DIR/stacks/tools/"

echo "Done! Compose files synced to nixos/stacks/"
