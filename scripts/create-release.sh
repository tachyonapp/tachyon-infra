#!/usr/bin/env bash
# Usage: ./scripts/create-release.sh <version> <api-sha> <workers-sha> <db-sha>
# Example: ./scripts/create-release.sh 0.2.0 abc1234 def5678 ghi9012

set -euo pipefail

VERSION="${1:?Usage: create-release.sh <version> <api-sha> <workers-sha> <db-sha>}"
API_SHA="${2:?Missing api-sha}"
WORKERS_SHA="${3:?Missing workers-sha}"
DB_SHA="${4:?Missing db-sha}"

MANIFEST_FILE="releases/manifest.json"

cat > "$MANIFEST_FILE" <<EOF
{
  "version": "${VERSION}",
  "created_at": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "description": "",
  "services": {
    "tachyon-api": {
      "sha": "${API_SHA}",
      "image": "ghcr.io/tachyonapp/tachyon-api",
      "tag": "${API_SHA}"
    },
    "tachyon-workers": {
      "sha": "${WORKERS_SHA}",
      "image": "ghcr.io/tachyonapp/tachyon-workers",
      "tag": "${WORKERS_SHA}"
    },
    "tachyon-db-migrate": {
      "sha": "${DB_SHA}",
      "image": "ghcr.io/tachyonapp/tachyon-db-migrate",
      "tag": "${DB_SHA}"
    }
  },
  "environments": {
    "staging": {
      "deployed_at": "",
      "deployed_by": ""
    },
    "production": {
      "deployed_at": "",
      "deployed_by": "",
      "approved_by": ""
    }
  }
}
EOF

echo "Release manifest created: ${MANIFEST_FILE} (v${VERSION})"
echo "  API:     ${API_SHA}"
echo "  Workers: ${WORKERS_SHA}"
echo "  DB:      ${DB_SHA}"