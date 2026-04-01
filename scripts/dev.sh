#!/usr/bin/env bash
# dev.sh — Start the full local development stack
#
# Starts the ngrok tunnel (for Clerk webhook delivery) and Docker Compose
# services in parallel. Both are stopped cleanly on Ctrl+C.
#
# Prerequisites:
#   - ngrok installed and authenticated (ngrok config add-authtoken <token>)
#   - Docker Desktop running
#   - tachyon-infra/.env present with CLERK_JWKS_URL, CLERK_ISSUER, CLERK_WEBHOOK_SECRET
#     (Docker Compose reads this file automatically for variable substitution)
#
# Usage:
#   ./scripts/dev.sh

set -euo pipefail

NGROK_DOMAIN="mandie-unstayable-lea.ngrok-free.dev"
API_PORT=4000

BOLD="\033[1m"
RESET="\033[0m"
GREEN="\033[32m"
YELLOW="\033[33m"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

echo -e "${BOLD}Starting Tachyon local dev stack...${RESET}"
echo ""

# Warn if the .env file is missing — Docker Compose needs it for CLERK_* substitution
if [ ! -f "${PROJECT_DIR}/.env" ]; then
  echo -e "${YELLOW}Warning: .env not found in $(basename "${PROJECT_DIR}") — CLERK_* vars will be empty.${RESET}"
  echo -e "${YELLOW}Create ${PROJECT_DIR}/.env with CLERK_JWKS_URL, CLERK_ISSUER, and CLERK_WEBHOOK_SECRET.${RESET}"
  echo ""
fi

# Verify ngrok is installed
if ! command -v ngrok &>/dev/null; then
  echo "Error: ngrok not found. Install it with: brew install ngrok"
  exit 1
fi

# Verify Docker is running
if ! docker info &>/dev/null; then
  echo "Error: Docker is not running. Start Docker Desktop and try again."
  exit 1
fi

cleanup() {
  echo ""
  echo -e "${YELLOW}Shutting down...${RESET}"
  # Kill background jobs (ngrok + docker compose)
  kill 0
}
trap cleanup EXIT INT TERM

# Start ngrok tunnel in background
echo -e "${GREEN}→ Starting ngrok tunnel${RESET} (${NGROK_DOMAIN} → localhost:${API_PORT})"
ngrok http --url="${NGROK_DOMAIN}" "${API_PORT}" --log=stdout --log-level=warn &

# Give ngrok a moment to establish the tunnel before services start receiving traffic
sleep 2

# Start Docker Compose in foreground (logs stream to terminal)
echo -e "${GREEN}→ Starting Docker Compose services${RESET}"
echo ""
docker compose up "$@"
