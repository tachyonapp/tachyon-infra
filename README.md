# Tachyon Infra

## Overview

`tachyon-infra` is the infrastructure-as-code (IaC) hub for the Tachyon platform. It owns the Docker Compose configurations, DigitalOcean App Spec, CI/CD deployment workflows, environment variable schemas, and release manifests for all Tachyon services.

This repo does **NOT** contain application source code. It is the single source of truth for how all Tachyon services are built, configured, and deployed together.

**Architecture:** Polyrepo — each service lives in its own repo and builds its own Docker image. `tachyon-infra` ties them together at the deployment layer.

---

## Repository Map

| Repo | Purpose | Local Path |
|------|---------|------------|
| [`tachyon-infra`](https://github.com/tachyonapp/tachyon-infra) | IaC hub — Docker Compose, App Spec, CI/CD, env schemas | `../tachyon-infra` |
| [`tachyon-api`](https://github.com/tachyonapp/tachyon-api) | GraphQL API gateway (Express + TypeScript) | `../tachyon-api` |
| [`tachyon-workers`](https://github.com/tachyonapp/tachyon-workers) | Background job processing (BullMQ + ValKey) | `../tachyon-workers` |
| [`tachyon-db`](https://github.com/tachyonapp/tachyon-db) | Database schema and migration runner (PostgreSQL) | `../tachyon-db` |
| [`tachyon-mobile`](https://github.com/tachyonapp/tachyon-mobile) | React Native mobile app (Expo) | `../tachyon-mobile` |

---

## Directory Structure

```
tachyon-infra/
├── .do/                          # DigitalOcean App Specs
│   ├── app.staging.yml           # Staging App Platform topology (APP_ENV=staging, standalone PG cluster)
│   └── app.prod.yml              # Production App Platform topology (APP_ENV=production, standalone PG cluster)
├── .github/
│   └── workflows/
│       ├── build-push.yml        # Reusable: build & push Docker image to GHCR
│       ├── test.yml              # Reusable: lint, test, secret scan
│       ├── validate.yml          # Infra CI: YAML lint, env validation, App Spec check
│       ├── deploy-staging.yml    # CD: deploy to staging (manual trigger)
│       └── deploy-prod.yml       # CD: deploy to production (manual trigger + approval)
├── env/                          # Environment variable schemas
│   ├── .env.example              # Master schema with all variables documented
│   ├── .env.local.example        # Local dev defaults (safe to use as-is)
│   ├── .env.staging.example      # Staging template (DO variable bindings)
│   └── .env.production.example   # Production template (DO variable bindings)
├── releases/
│   ├── manifest.json             # Current release: pinned image SHAs per service
│   └── README.md                 # Release manifest format and workflow docs
├── scripts/
│   ├── setup.sh                  # Clone all sibling repos and validate layout
│   ├── validate-env.sh           # Check env files for variable consistency
│   └── create-release.sh         # Generate a new release manifest
├── templates/
│   ├── Dockerfile.node           # Multi-stage Node.js Dockerfile template
│   └── .dockerignore             # Standard .dockerignore for Node services
├── docker-compose.yml            # Local dev: all services (build or GHCR mode)
├── docker-compose.test.yml       # Integration test environment (ephemeral)
├── package.json                  # YAML lint tooling only
└── README.md                     # This file
```

---

## Prerequisites

| Tool | Version | Install |
|------|---------|---------|
| Docker Desktop | Latest | [docker.com](https://www.docker.com/products/docker-desktop/) |
| Node.js | 20+ | [nodejs.org](https://nodejs.org/) or `nvm install 20` |
| git | Any | Pre-installed on macOS/Linux |
| GitHub CLI (`gh`) | Latest | `brew install gh` |

---

## Quick Start

```bash
# 1. Clone this repo
git clone https://github.com/tachyonapp/tachyon-infra.git
cd tachyon-infra

# 2. Clone all service repos as siblings
./scripts/setup.sh

# 3. Install YAML lint tooling
npm install

# 4. Start the full local stack (builds from sibling repos)
docker compose up

# 5. Verify the API is healthy
curl http://localhost:4000/health
```

Expected response:

```json
{
  "status": "healthy",
  "version": "unknown",
  "timestamp": "2026-01-01T00:00:00.000Z",
  "checks": { "postgres": "connected", "valkey": "connected" }
}
```

---

## Local Development

### Docker Compose Modes

**Mode 1 — Build from source (default)**

Builds images from sibling repos on disk. Use when actively developing services.

```bash
export NODE_AUTH_TOKEN=<your-github-pat>  # GitHub PAT with read:packages scope
docker compose up
```

Requires all service repos cloned as siblings (`../tachyon-api`, `../tachyon-workers`, `../tachyon-db`).

`NODE_AUTH_TOKEN` is required so Docker can pull `@tachyonapp/tachyon-db` from GitHub Packages during the build. It is passed as a BuildKit secret and never written to any image layer.

---

**Mode 2 — Pull pre-built images from GHCR**

Pulls the latest published images. Use when you only need the stack running and aren't modifying service code.

```bash
docker compose --profile ghcr up
```

Requires `docker login ghcr.io` with a GitHub PAT that has `read:packages` scope.

---

**Mode 3 — Infrastructure only**

Starts only PostgreSQL and ValKey. Use when running a single service locally with `npm run dev`.

```bash
docker compose up postgres valkey
```

Then in the service repo:

```bash
# tachyon-api
cp ../tachyon-infra/env/.env.local.example .env.local
npm run dev
```

### Bull Board Dashboard

After running `docker compose up` (build-from-source mode), the BullMQ job queue dashboard is available at:

```
http://localhost:4000/internal/bull-board
```

No authentication is required in local development. All 6 queues (`scan:dispatch`, `scan:bot`, `expiry`, `reconciliation`, `notification`, `summary`) are visible once the workers service has started.

> **Note:** Bull Board is only available in build-from-source mode (`docker compose up`). It is not available in GHCR mode (`--profile ghcr`) because the production image excludes devDependencies.

### Hot Reload

In build mode, `docker-compose.yml` mounts `../tachyon-api/src` and `../tachyon-workers/src` into the running containers. Changes to source files are reflected immediately when services are started with `tsx watch`.

### Useful Commands

```bash
# Tail logs for a specific service
docker compose logs -f api

# Restart a single service after code changes
docker compose restart api

# Run integration tests against ephemeral containers
docker compose -f docker-compose.test.yml up --abort-on-container-exit

# Stop everything and remove volumes (fresh start)
docker compose down -v
```

---

## Environment Variables

All environment variable schemas live in `env/`. **NEVER commit actual `.env` files.**

| File | Purpose |
|------|---------|
| `env/.env.example` | Master schema — every variable across all services, with documentation |
| `env/.env.local.example` | Local development defaults (safe to use as-is with Docker Compose) |
| `env/.env.staging.example` | Staging template using DigitalOcean variable bindings |
| `env/.env.production.example` | Production template using DigitalOcean variable bindings |

### Local Setup

```bash
# Copy local defaults into the API repo
cp env/.env.local.example ../tachyon-api/.env.local

# Copy for workers
cp env/.env.local.example ../tachyon-workers/.env.local
```

### Validate Consistency

Check that all environment files define the same set of variables:

```bash
./scripts/validate-env.sh
```

This is also run automatically in CI (`validate.yml`).

Run this locally whenever you:
- Add a new environment variable to any service
- Remove an environment variable
- Change which environments a variable applies to

**What it checks:** Every variable in `env/.env.example` (the master schema) must be present in `.env.local.example` and `.env.staging.example`. Variables intentionally absent from production (e.g. `BULL_BOARD_USERNAME`, `BULL_BOARD_PASSWORD`) are listed in the `PRODUCTION_EXCLUDED_VARS` array at the top of `scripts/validate-env.sh` and skipped when validating `.env.production.example`.

**Adding a new variable:**
1. Add it to `env/.env.example` with a comment explaining its purpose and which service uses it
2. Add it to `env/.env.local.example`, `env/.env.staging.example`, and `env/.env.production.example` (or only the environments it applies to)
3. If it is intentionally absent from production, add its name to `PRODUCTION_EXCLUDED_VARS` in `scripts/validate-env.sh`
4. Run `./scripts/validate-env.sh` to confirm zero failures before committing

---

## CI/CD

### Service Repo Pipeline (per repo)

```
PR opened
  └─ lint + test + secret scan
       └─ merged to main
            └─ build Docker image
                 └─ push to GHCR (ghcr.io/tachyonapp/<service>:<sha> + :latest)
                      └─ vulnerability scan (Trivy)
```

Service repos use two reusable workflow templates defined in this repo:

- `.github/workflows/test.yml` — lint, test, lockfile check, secret scan
- `.github/workflows/build-push.yml` — Docker build, GHCR push, Trivy scan, image size check

### Infra Repo Pipeline

```
PR opened / push to main
  └─ validate.yml runs in parallel:
       ├─ YAML lint (docker-compose.yml, docker-compose.test.yml, .do/app.staging.yml, .do/app.prod.yml)
       ├─ env schema validation (validate-env.sh)
       ├─ App Spec structure check (required keys)
       └─ secret scan (TruffleHog)
```

---

## Deployment

### First-Time App Provisioning

Before deploying for the first time (or after destroying and recreating an app), the DO App Platform secrets must be set manually. These are not auto-bound from the cluster — they will be empty until explicitly set.

**Step 1 — Create the app from the spec:**

```bash
# Staging
doctl apps create --spec .do/app.staging.yml

# Production
doctl apps create --spec .do/app.prod.yml
```

**Step 2 — Set secrets in the DO console (or via `doctl apps update`):**

Each service requires its own `DATABASE_URL` because they connect as different DB users:

| App | Service | Secret | Value |
|-----|---------|--------|-------|
| Staging | `db-migrate` | `DATABASE_URL` | `postgres://tachyon_migrate:<pw>@<host>:<port>/<db>?sslmode=require` |
| Staging | `tachyon-api` | `DATABASE_URL` | `postgres://tachyon_app:<pw>@<host>:<port>/<db>?sslmode=require` |
| Staging | `tachyon-api` | `DB_ENCRYPTION_KEY` | 32-byte hex — generate with `openssl rand -hex 32` |
| Staging | `tachyon-workers` | `DATABASE_URL` | `postgres://tachyon_app:<pw>@<host>:<port>/<db>?sslmode=require` |
| Staging | `tachyon-workers` | `DB_ENCRYPTION_KEY` | Same value as api |
| Production | *(same 5 secrets)* | — | Production credentials |

The `tachyon_migrate` and `tachyon_app` DB users must be provisioned on the cluster before this step. See the `tachyon-db` repo's `scripts/README.md` for the SQL provisioning commands.

> **Why `DATABASE_URL` is not auto-bound:** All services connect as privilege-separated users (`tachyon_app` for API/workers, `tachyon_migrate` for migrations) rather than the cluster's default `doadmin` user. DO's automatic `${component.DATABASE_URL}` binding always resolves to `doadmin` credentials and cannot be used here.

---

### Staging

Triggered manually from the Actions tab in `tachyon-infra`.

1. Go to **Actions → Deploy to Staging → Run workflow**
2. Optionally provide image SHAs per service (leave blank to use `latest`)
3. The workflow:
   - Updates the App Spec with the resolved image tags
   - Deploys to DigitalOcean App Platform via `doctl`
   - Polls `/health` until the deployment is confirmed healthy
   - Writes the deployed SHAs and timestamp back to `releases/manifest.json`

**Required GitHub secrets** (set on `tachyon-infra` repo):

| Secret | Description |
|--------|-------------|
| `DIGITALOCEAN_ACCESS_TOKEN` | DO API token with App Platform write access |
| `DO_APP_ID` | Staging App Platform app ID |

### Production

Triggered manually and **requires manual approval** via the `production` GitHub Actions environment.

1. Deploy to staging first and verify
2. Create a release manifest: `./scripts/create-release.sh <version> <api-sha> <workers-sha> <db-sha>`
3. Go to **Actions → Deploy to Production → Run workflow**
4. Enter the release version (must match `releases/manifest.json`)
5. A reviewer approves the deployment in the GitHub UI
6. The workflow:
   - Validates the version matches the manifest
   - Verifies staging deployment exists (blocks production if staging hasn't been done)
   - Deploys the exact same image SHAs that were validated in staging
   - Polls `/health` on production
   - Updates the manifest with production deployment metadata

**Required GitHub secrets** (set on `tachyon-infra` repo):

| Secret | Description |
|--------|-------------|
| `DIGITALOCEAN_PROD_ACCESS_TOKEN` | Separate DO API token for production |
| `DO_PROD_APP_ID` | Production App Platform app ID |

---

## Release Management

The `releases/manifest.json` file tracks which image versions (commit SHAs) across all service repos have been validated together.

### Create a Release

```bash
./scripts/create-release.sh <version> <api-sha> <workers-sha> <db-sha>

# Example
./scripts/create-release.sh 0.2.0 abc1234 def5678 ghi9012
```

This overwrites `releases/manifest.json` with the new version and SHAs. Commit and push the updated manifest before triggering a deployment.

### Release Flow

```
create-release.sh
  └─ manifest.json (SHAs pinned)
       └─ deploy-staging.yml (deploys + writes staging metadata)
            └─ manifest.json (staging.deployed_at populated)
                 └─ deploy-prod.yml (reads manifest, enforces staging-first, deploys)
                      └─ manifest.json (production.deployed_at populated)
```

See [`releases/README.md`](releases/README.md) for the full manifest format, field reference, and workflow integration details.

---

## Troubleshooting

**Port already in use (5432 or 6379)**

Another PostgreSQL or ValKey instance is running locally. Stop it or change the host port in `docker-compose.yml`.

```bash
# Find what's using the port
lsof -i :5432
lsof -i :6379
```

**Sibling repos not found by Docker Compose**

Docker Compose build contexts use relative paths (`../tachyon-api`). The service repos must be cloned as siblings of `tachyon-infra`. Run `./scripts/setup.sh` to clone any missing repos.

**Stale Docker volumes causing migration errors**

If migrations fail after a schema reset, remove the persistent volume and restart:

```bash
docker compose down -v
docker compose up
```

**`npm run validate:yaml` fails**

The `yaml-lint` package must be installed:

```bash
npm install
npm run validate:yaml
```

**GHCR pull failing in `--profile ghcr` mode**

You must be authenticated to `ghcr.io`:

```bash
echo $GITHUB_TOKEN | docker login ghcr.io -u <your-github-username> --password-stdin
```

**`doctl` not found in deployment workflow**

The `digitalocean/action-doctl@v2` action installs `doctl` automatically. If running locally, install it via `brew install doctl` and authenticate with `doctl auth init`.
