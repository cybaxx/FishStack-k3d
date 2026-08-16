# Wetfish Web-Services K8s

Kubernetes migration of wetfish web-services, running on k3d (local dev) and k3s (staging/production), with multi-environment Kustomize overlays and FluxCD GitOps for staging/prod.

---

## Environments

| Environment | Namespace | Hostnames | Registry | Branch |
|-------------|-----------|-----------|----------|--------|
| dev | `wetfish-dev` | `*.wetfish.local` | `wetfish-registry:5000` (k3d local) | local builds |
| staging | `wetfish-staging` | `staging-<svc>.wetfish.net` | `ghcr.io/cybaxx/web-services-k8s` | `main` |
| prod | `wetfish-prod` | `<svc>.wetfish.net` | `ghcr.io/cybaxx/web-services-k8s` | `release` |

### Services

| Service | Stack | Database |
|---------|-------|----------|
| **wiki** | PHP 8.2 + nginx (sidecar) | MariaDB 10.10 |
| **home** | Node 20 build → nginx (static) | None |
| **glitch** | PHP 5.6 + nginx (sidecar) | None |
| **click** | PHP 5.6 + nginx (sidecar) | MariaDB 10.10 |
| **danger** | PHP 5.6 + nginx (sidecar) | MariaDB 10.10 |
| **forum** | SMF 2.1.6 + PHP 8.4 | MariaDB 10.11 |

Observability is handled by [FishVision](https://github.com/wetfish/FishVision) (separate repo) — this repo no longer contains a monitoring stack.

---

## Quick Start (dev)

### Prerequisites
- Docker Desktop or Docker Engine
- k3d
- kubectl
- helm

### 1. Clone and bring up
```bash
git clone --recurse-submodules git@github.com:cybaxx/FishStack-k3d.git
cd FishStack-k3d

# Full bring-up: cluster + infra + builds + deploy + hosts
./scripts/up.sh

# Add DNS entries to /etc/hosts (if not done by up.sh)
sudo ./scripts/setup-hosts.sh
```

`up.sh` creates a k3d cluster (1 server, 2 agents, local registry on `:5000`), deploys Traefik and cert-manager, builds and pushes all service images, and deploys every service to `wetfish-dev`. Use `--skip-cluster`, `--skip-build`, or `--skip-hosts` to reuse existing state.

### 2. Load database schemas (first deploy only)
```bash
kubectl exec -i deployment/wiki-mysql -n wetfish-dev -- mysql -uroot -pwikipass wikidb < services/wiki/src/wwwroot/src/schema.sql
kubectl exec -i deployment/click-mysql -n wetfish-dev -- mysql -uroot -pclickpass clickdb < services/click/src/schema.sql
kubectl exec -i deployment/danger-mysql -n wetfish-dev -- mysql -uroot -pdangerpass dangerdb < services/danger/src/schema.sql
```

### 3. Access services
```
http://wiki.wetfish.local:8080
http://home.wetfish.local:8080
http://glitch.wetfish.local:8080
http://click.wetfish.local:8080
http://danger.wetfish.local:8080
```

---

## Scripts

| Script | Purpose |
|--------|---------|
| `up.sh` | Full bring-up (cluster + infra + builds + deploy + hosts) |
| `setup-dev.sh` | Create the k3d cluster only |
| `cleanup.sh` | Tear down cluster and Docker resources |
| `setup-hosts.sh` | Manage `/etc/hosts` entries |
| `deploy.sh` | Deploy a service to an environment |
| `generate-secrets.sh` | Generate per-environment k8s secrets |
| `bootstrap-flux.sh` | Bootstrap FluxCD on staging/prod |
| `test-deployment.sh` | Run health checks against a deployment |
| `test-setup.sh` | Validate cluster setup |
| `fix-wiki.sh` | Wiki-specific repair tasks |
| `sync-from-vultr.sh` | Sync data from the legacy Vultr host |

### Cluster lifecycle
```bash
./scripts/up.sh                          # Full bring-up
./scripts/cleanup.sh                     # Tear down
sudo ./scripts/setup-hosts.sh            # Manage DNS entries
k3d cluster start wetfish-dev            # Start existing cluster
k3d cluster stop wetfish-dev             # Stop cluster
```

### Deploying
```bash
./scripts/deploy.sh [--env dev|staging|prod] <service> [delete]

./scripts/deploy.sh wiki                 # Deploy wiki to dev (default)
./scripts/deploy.sh --env staging wiki   # Deploy wiki to staging
./scripts/deploy.sh --env prod wiki      # Deploy wiki to prod
./scripts/deploy.sh --env dev wiki delete
```

### Secrets
```bash
./scripts/generate-secrets.sh                        # Dev secrets (default passwords)
./scripts/generate-secrets.sh --random               # Dev secrets (random passwords)
./scripts/generate-secrets.sh --env staging --random # Staging secrets
```

### Debugging
```bash
./scripts/test-deployment.sh wetfish-dev wiki

kubectl get pods -n wetfish-dev
kubectl logs deployment/wiki-web -n wetfish-dev -c nginx -f
kubectl logs deployment/wiki-web -n wetfish-dev -c php-fpm -f
kubectl exec -it deployment/wiki-web -n wetfish-dev -c php-fpm -- bash

# Preview a Kustomize overlay before applying
kubectl kustomize services/wiki/k8s/overlays/dev/
```

---

## Project Structure

```
FishStack-k3d/
├── .github/workflows/          # CI/CD pipelines (GitHub Actions)
├── clusters/                   # FluxCD GitOps (staging + prod)
│   ├── staging/                # apps/, infrastructure/, image-automation/
│   └── prod/                   # apps/, infrastructure/
├── services/                   # Application services
│   ├── wiki/                   # PHP 8.2 + MariaDB
│   ├── home/                   # Node 20 build → static nginx
│   ├── glitch/                 # PHP 5.6
│   ├── click/                  # PHP 5.6 + MariaDB
│   ├── danger/                 # PHP 5.6 + MariaDB
│   └── forum/                  # SMF 2.1.6 + MariaDB
├── infrastructure/             # Core infrastructure
│   ├── traefik/                # Traefik v2.11 ingress controller (raw manifests)
│   ├── cert-manager/           # ACME issuers
│   ├── network-policies/       # Network policy defaults
│   ├── resource-limits/        # Default resource limits
│   └── namespaces.yaml         # wetfish-system/dev/staging/prod
├── scripts/                    # Automation scripts
└── docs/                       # Documentation
```

Each service lives under `services/<name>/` with:
- `src/` — git submodule pointing at the upstream wetfish repo (application source)
- `k8s/base/` — environment-agnostic manifests (configmap, mysql, web, ingress)
- `k8s/overlays/{dev,staging,prod}/` — per-environment Kustomize overlays
- `config/` — k8s-modified config files (nginx.conf, php.ini, Settings.php, etc.)
- `Dockerfile.*` — container definitions (nginx / php-fpm sidecars)

Base manifests use placeholder image names (e.g. `WIKI_NGINX_IMAGE:latest`) that Kustomize `images` transformers replace per environment. Overlays set namespace, registry, ingress hostnames, TLS, and env-specific values.

---

## CI/CD

GitHub Actions builds container images to GHCR on push. A reusable `build-service.yml` (`workflow_call`) handles checkout, GHCR login, metadata, and docker build+push; per-service workflows trigger on changes to their `services/<name>/**` paths:

| Workflow | Service | Components |
|----------|---------|------------|
| `build-wiki.yml` | wiki | nginx, php |
| `build-home.yml` | home | app |
| `build-glitch.yml` | glitch | nginx, php |
| `build-click.yml` | click | nginx, php |
| `build-danger.yml` | danger | nginx, php |
| `build-forum.yml` | forum | nginx, php |

Image tags: `staging-<component>` on push to `main`, `prod-<component>` on push to `release`, plus branch/sha/pr tags.

```
feature/branch -> PR -> main -> (merge to release for prod)
```

---

## GitOps

Staging and production are managed with FluxCD. The `clusters/` directory contains the Flux configuration (`apps/`, `infrastructure/`, and `image-automation/`) for each environment.

```bash
export GITHUB_TOKEN=...
./scripts/bootstrap-flux.sh staging
./scripts/bootstrap-flux.sh prod
```

---

## Roadmap

### Phase 1: Foundation (complete)
- [x] k3d cluster with Traefik ingress
- [x] Wiki service (pilot migration)
- [x] Home, glitch, click, danger services
- [x] CI/CD workflows
- [x] Multi-environment support (dev/staging/prod overlays)

### Phase 2: Production Ready (in progress)
- [x] Forum service (SMF 2.1.6, live at `wetfishonline.com`)
- [~] FluxCD GitOps (scaffolded in `clusters/` + `bootstrap-flux.sh`, not yet live)
- [ ] Security hardening (see `docs/security-audit-action-items.md`)
- [ ] Backup strategies (manual mysqldump only)
- [ ] TLS/HTTPS enforcement (cert-manager deployed; forced HTTP→HTTPS redirect pending)

### Phase 3: Scale Out
- [ ] FluxCD rollout to staging/prod (replace manual `kubectl` deploy)
- [ ] Sealed secrets / external secret store
- [ ] Automated promotion to production
