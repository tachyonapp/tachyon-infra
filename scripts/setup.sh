#!/usr/bin/env bash

# Tachyon Development Environment Setup
# =============================================================================
# USAGE
# =============================================================================
# - Clones all service repos as siblings and validates the directory layout.
# - Usage: ./scripts/setup.sh
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INFRA_DIR="$(dirname "$SCRIPT_DIR")"
PARENT_DIR="$(dirname "$INFRA_DIR")"

ORG="tachyonapp"
REPOS=("tachyon-api" "tachyon-workers" "tachyon-db" "tachyon-mobile")

echo "=== Tachyon Development Setup ==="
echo "Infra directory: ${INFRA_DIR}"
echo "Parent directory: ${PARENT_DIR}"
echo ""

# Clone missing repos
for REPO in "${REPOS[@]}"; do
  REPO_DIR="${PARENT_DIR}/${REPO}"
  if [ -d "$REPO_DIR" ]; then
    echo "[OK] ${REPO} already exists at ${REPO_DIR}"
  else
    echo "[CLONE] Cloning ${REPO}..."
    git clone "https://github.com/${ORG}/${REPO}.git" "$REPO_DIR"
  fi
done

echo ""

# Validate layout
echo "=== Validating Directory Layout ==="
ALL_OK=true
for REPO in "${REPOS[@]}"; do
  REPO_DIR="${PARENT_DIR}/${REPO}"
  if [ ! -d "$REPO_DIR" ]; then
    echo "[FAIL] Missing: ${REPO_DIR}"
    ALL_OK=false
  elif [ ! -f "$REPO_DIR/package.json" ]; then
    echo "[WARN] ${REPO}: No package.json found"
  else
    echo "[OK] ${REPO}"
  fi
done

if [ "$ALL_OK" = true ]; then
  echo ""
  echo "=== Setup Complete ==="
  echo "All repos cloned. Next steps:"
  echo "  1. Copy env config: cp env/.env.local.example .env.local"
  echo "  2. Start services:  docker compose up"
  echo "  3. API health:      curl http://localhost:4000/health"
else
  echo ""
  echo "[ERROR] Some repos are missing. Check output above."
  exit 1
fi