#!/usr/bin/env bash

# Tachyon Development Environment Env Validation
# =============================================================================
# USAGE
# =============================================================================
# - Checks that every variable in .env.example appears in all environment-specific files.
# - Run: ./scripts/validate-env.sh
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_DIR="$(dirname "$SCRIPT_DIR")/env"

# Extract non-comment, non-empty variable names from a file
extract_vars() {
  grep -E '^[A-Z_]+=' "$1" | cut -d= -f1 | sort
}

# Extract commented-out future variables
extract_future_vars() {
  grep -E '^#\s*[A-Z_]+=' "$1" | sed 's/^#\s*//' | cut -d= -f1 | sort
}

echo "=== Validating Environment Variable Schema ==="

# Check all env files exist
FILES=(".env.example" ".env.local.example" ".env.staging.example" ".env.production.example")
for FILE in "${FILES[@]}"; do
  if [ ! -f "${ENV_DIR}/${FILE}" ]; then
    echo "[FAIL] Missing: env/${FILE}"
    exit 1
  fi
done

# Get active vars from the schema (excluding future/commented vars)
SCHEMA_VARS=$(extract_vars "${ENV_DIR}/.env.example")

# Variables intentionally absent from production (dev/staging only).
# Add to this list when a variable is deliberately excluded from .env.production.example.
PRODUCTION_EXCLUDED_VARS=(
  "BULL_BOARD_USERNAME"
  "BULL_BOARD_PASSWORD"
)

# Build a filtered schema for production by removing excluded vars
production_schema() {
  local vars="$SCHEMA_VARS"
  for var in "${PRODUCTION_EXCLUDED_VARS[@]}"; do
    vars=$(echo "$vars" | grep -v "^${var}$")
  done
  echo "$vars"
}

# Check each environment file has all schema vars
ALL_OK=true
for FILE in ".env.local.example" ".env.staging.example" ".env.production.example"; do
  ENV_VARS=$(extract_vars "${ENV_DIR}/${FILE}")

  if [ "$FILE" = ".env.production.example" ]; then
    EXPECTED=$(production_schema)
  else
    EXPECTED="$SCHEMA_VARS"
  fi

  MISSING=$(comm -23 <(echo "$EXPECTED") <(echo "$ENV_VARS"))
  if [ -n "$MISSING" ]; then
    echo "[FAIL] ${FILE} missing variables:"
    echo "$MISSING" | sed 's/^/  - /'
    ALL_OK=false
  else
    echo "[OK] ${FILE} -- all variables present"
  fi
done

if [ "$ALL_OK" = true ]; then
  echo ""
  echo "All environment files are consistent."
else
  echo ""
  echo "[ERROR] Environment variable inconsistencies found."
  exit 1
fi