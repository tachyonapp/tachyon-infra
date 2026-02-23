# Release Manifest System

## Overview

Tachyon uses a polyrepo architecture where each service (API, Workers, DB, UI...) lives in its own repository and builds its own Docker image independently. The release manifest system solves the cross-repo versioning problem: it tracks which image versions (commit SHAs) across all service repos have been tested together and are safe to deploy as a unit.

Without this system, there is no guarantee that the `latest` tag on `tachyon-api` is compatible with the `latest` tag on `tachyon-workers`. The manifest acts as a pinned snapshot of known-compatible versions.

## Manifest Format

The manifest lives at `releases/manifest.json`:

```json
{
  "version": "0.2.0",
  "created_at": "2026-02-23T12:00:00Z",
  "description": "Initial infrastructure stub release",
  "services": {
    "tachyon-api": {
      "sha": "abc1234",
      "image": "ghcr.io/tachyonapp/tachyon-api",
      "tag": "abc1234"
    },
    "tachyon-workers": {
      "sha": "def5678",
      "image": "ghcr.io/tachyonapp/tachyon-workers",
      "tag": "def5678"
    },
    "tachyon-db-migrate": {
      "sha": "ghi9012",
      "image": "ghcr.io/tachyonapp/tachyon-db-migrate",
      "tag": "ghi9012"
    }
  },
  "environments": {
    "staging": {
      "deployed_at": "2026-02-23T12:05:00Z",
      "deployed_by": "engineer"
    },
    "production": {
      "deployed_at": "2026-02-23T14:00:00Z",
      "deployed_by": "engineer",
      "approved_by": "engineer"
    }
  }
}
```

### Field Reference

| Field | Description |
|-------|-------------|
| `version` | Semantic version for this release (e.g., `0.2.0`) |
| `created_at` | ISO 8601 timestamp when the manifest was created |
| `description` | Optional description of what this release contains |
| `services.<name>.sha` | Git commit SHA from the service repo |
| `services.<name>.image` | Full GHCR image path |
| `services.<name>.tag` | Image tag used for deployment (matches SHA) |
| `environments.staging.deployed_at` | Timestamp of last staging deployment |
| `environments.staging.deployed_by` | GitHub actor who triggered staging deploy |
| `environments.production.deployed_at` | Timestamp of last production deployment |
| `environments.production.deployed_by` | GitHub actor who triggered production deploy |
| `environments.production.approved_by` | GitHub actor who approved the production deploy |

## Creating a Release

Use the helper script to generate a new manifest from known-good commit SHAs:

```bash
./scripts/create-release.sh <version> <api-sha> <workers-sha> <db-sha>
```

Example:

```bash
./scripts/create-release.sh 0.2.0 abc1234 def5678 ghi9012
```

This overwrites `releases/manifest.json` with the new version, populates `created_at` with the current UTC timestamp, and sets all service SHAs/tags. Environment deployment metadata is left empty until the deployment workflows run.

## Deployment Workflow Integration

The manifest is consumed by two GitHub Actions workflows in `tachyon-infra`:

### Staging (`deploy-staging.yml`)

1. Triggered manually via `workflow_dispatch` with optional SHA overrides per service
2. Resolves image tags (provided SHAs or `latest`)
3. Updates the DO App Spec with resolved tags and deploys via `doctl`
4. Verifies deployment health by polling `/health`
5. **Writes back to the manifest** — updates `services.*.tag` with the deployed SHAs and sets `environments.staging.deployed_at` and `deployed_by`
6. Commits the updated manifest to the repo

### Production (`deploy-prod.yml`)

1. Triggered manually via `workflow_dispatch` with a required `confirm_version` input
2. **Reads the manifest** — validates that `confirm_version` matches `manifest.version`
3. **Enforces staging-first** — verifies `environments.staging.deployed_at` is populated (blocks production deploy if staging hasn't been done)
4. Extracts the exact SHAs from the manifest to deploy the same versions that were validated in staging
5. Deploys via `doctl` and verifies health
6. **Writes back to the manifest** — sets `environments.production.deployed_at`, `deployed_by`, and `approved_by`
7. Commits the updated manifest to the repo

### Flow

```
create-release.sh → manifest.json → deploy-staging.yml → manifest.json (updated) → deploy-prod.yml → manifest.json (updated)
```

This ensures production always receives the exact same image versions that were validated in staging.
