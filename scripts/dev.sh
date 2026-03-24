#!/usr/bin/env bash
# dev.sh — Start the full local development stack
#
# Starts the ngrok tunnel (for Clerk webhook delivery) and Docker Compose
# services in parallel. Both are stopped cleanly on Ctrl+C.
#
# Prerequisites:
#   - ngrok installed and authenticated (ngrok config add-authtoken <token>)
#   - Docker Desktop running
#   - CLERK_WEBHOOK_SECRET set in ../tachyon-api/.env
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

echo -e "${BOLD}Starting Tachyon local dev stack...${RESET}"
echo ""

# Export Clerk vars from tachyon-api/.env so docker-compose substitution picks them up.
# Only exports variables that aren't already set in the environment.
API_ENV="$(dirname "$0")/../../tachyon-api/.env"
if [ -f "$API_ENV" ]; then
  while IFS='=' read -r key value; do
    # Skip comments and blank lines
    [[ "$key" =~ ^#.*$ || -z "$key" ]] && continue
    # Only export CLERK_* vars; don't override existing env
    if [[ "$key" == CLERK_* && -z "${!key:-}" ]]; then
      export "$key=$value"
    fi
  done < "$API_ENV"
else
  echo -e "${YELLOW}Warning: ../tachyon-api/.env not found — CLERK_* vars may be missing${RESET}"
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
