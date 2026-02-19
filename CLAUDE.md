# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Kubernetes migration of wetfish web-services from Docker Compose to a k3d cluster with full observability (Prometheus, Grafana, Loki, Tempo).

### Migration Phases
1. **Foundation (current)** - Services migrated, k3d cluster, CI/CD, monitoring stack
2. **Production Ready** - Production cluster, security hardening, backups
3. **Scale Out** - Forum service, multi-env, GitOps

### Current Status
- **5 services running in k3d cluster**: wiki, home, glitch, click, danger
- **Multi-environment support**: dev / staging / prod via Kustomize overlays
- Forum service deferred (complex SMF setup, needs separate planning)
- GitHub Actions CI/CD workflows for all 5 services (reusable workflow pattern)
- Infrastructure deployed (Traefik, cert-manager, namespaces for dev/staging/prod)
- **Monitoring stack deployed**: Prometheus, Grafana, Alertmanager, Loki, Tempo, Promtail
- Scripts complete (up, deploy, cleanup, hosts, generate-secrets, testing)

### Known Issues & Lessons Learned
- Wiki Dockerfiles use Debian bookworm default packages (PHP 8.2, Node 18) - NodeSource/Sury repos removed (EOL/broken GPG keys)
- Click, danger, glitch use `php:5.6-fpm-alpine` Docker image (Sury PHP 5.6 repos broken)
- MySQL deployment uses `strategy: Recreate` (required for RWO PVCs)
- MySQL `sql_mode = ""` needed for legacy PHP code that passes `'NULL'` strings for auto-increment
- MySQL `character-set-server` must have matching `collation-server` (MariaDB 10.10 defaults to utf8mb4 collation)
- DB schemas must be loaded manually on first deploy:
  - `kubectl exec -i deployment/wiki-mysql -n wetfish-dev -- mysql -uroot -pwikipass wikidb < services/wiki/src/wwwroot/src/schema.sql`
  - `kubectl exec -i deployment/click-mysql -n wetfish-dev -- mysql -uroot -pclickpass clickdb < services/click/src/schema.sql`
  - `kubectl exec -i deployment/danger-mysql -n wetfish-dev -- mysql -uroot -pdangerpass dangerdb < services/danger/src/schema.sql`
- If k3d agent nodes show NotReady, restart them: `docker restart k3d-wetfish-dev-agent-0 k3d-wetfish-dev-agent-1`
- Security contexts: nginx, php-fpm, and MariaDB images all run as root. Do NOT use `runAsNonRoot: true` or `capabilities: drop: ["ALL"]` on these containers. Traefik is the exception (supports non-root via `runAsUser: 65532`).
- Wiki liveness probe uses `tcpSocket` (not `httpGet`) because the app returns 500 before DB schema is loaded
- Traefik HTTP→HTTPS redirect is disabled in dev (breaks local access on port 8080)
- ServiceMonitor CRDs only exist when monitoring stack is deployed; deploy scripts tolerate partial apply failures

## Environments

| Environment | Namespace | Hostnames | Registry | Branch |
|-------------|-----------|-----------|----------|--------|
| dev | wetfish-dev | `*.wetfish.local` | `wetfish-registry:5000` (k3d local) | local builds |
| staging | wetfish-staging | `*.staging.wetfish.net` | `ghcr.io/cybaxx/web-services-k8s` | `main` |
| prod | wetfish-prod | `*.wetfish.net` | `ghcr.io/cybaxx/web-services-k8s` | `release` |

## Key Commands

### Cluster Lifecycle
```bash
./scripts/up.sh                          # Full stack bring-up (cluster + infra + builds + deploy)
./scripts/up.sh --skip-cluster --skip-build  # Redeploy without rebuilding
./scripts/up.sh --with-monitoring        # Include monitoring stack
./scripts/setup-dev.sh                   # Create k3d cluster only (1 server, 2 agents, local registry on :5000)
./scripts/cleanup.sh                     # Tear down cluster and Docker resources
sudo ./scripts/setup-hosts.sh            # Add service DNS entries to /etc/hosts
k3d cluster start wetfish-dev            # Start existing cluster
k3d cluster stop wetfish-dev             # Stop cluster
```

### Building Images (dev)
```bash
docker build -t localhost:5000/wiki:nginx -f services/wiki/Dockerfile.nginx services/wiki/
docker build -t localhost:5000/wiki:php -f services/wiki/Dockerfile.php services/wiki/
docker push localhost:5000/wiki:nginx
docker push localhost:5000/wiki:php
```

### Deploying Services
```bash
./scripts/deploy.sh [--env dev|staging|prod] <service> [delete]
# Examples:
./scripts/deploy.sh wiki                      # Deploy wiki to dev (default)
./scripts/deploy.sh --env dev wiki            # Deploy wiki to dev
./scripts/deploy.sh --env staging wiki        # Deploy wiki to staging
./scripts/deploy.sh --env prod wiki           # Deploy wiki to prod
./scripts/deploy.sh --env dev wiki delete     # Remove wiki from dev
./scripts/deploy.sh monitoring                # Deploy monitoring stack (Helm)
./scripts/deploy.sh traefik                   # Deploy Traefik (Helm)
```

### Generating Secrets
```bash
./scripts/generate-secrets.sh                 # Generate dev secrets (default passwords)
./scripts/generate-secrets.sh --random        # Generate dev secrets (random passwords)
./scripts/generate-secrets.sh --env staging --random  # Generate staging secrets
```

### Testing & Debugging
```bash
./scripts/test-deployment.sh wetfish-dev wiki  # Run health checks
kubectl get pods -n wetfish-dev
kubectl logs deployment/wiki-web -n wetfish-dev -c nginx -f
kubectl logs deployment/wiki-web -n wetfish-dev -c php-fpm -f
kubectl exec -it deployment/wiki-web -n wetfish-dev -c php-fpm -- bash
kubectl port-forward svc/prometheus-grafana 3000:80 -n wetfish-monitoring
```

### Kustomize Dry-Run
```bash
# Preview what will be deployed
kubectl kustomize services/wiki/k8s/overlays/dev/
kubectl kustomize services/wiki/k8s/overlays/staging/
```

## Architecture

### Namespaces
- **wetfish-system** - Infrastructure (Traefik ingress controller)
- **wetfish-dev** - Development services (wiki, home, glitch, click, danger)
- **wetfish-staging** - Staging services
- **wetfish-prod** - Production services
- **wetfish-monitoring** - Observability stack (Prometheus, Grafana, Loki, Tempo)

### Service Layout (Kustomize)
Each service lives under `services/<name>/` with:
- `src/` - Git submodule pointing to upstream wetfish repo (application source code)
- `k8s/base/` - Environment-agnostic Kubernetes manifests (configmap, mysql, web, ingress, etc.)
- `k8s/overlays/dev/` - Dev overlay (local registry, *.wetfish.local, local-path storage)
- `k8s/overlays/staging/` - Staging overlay (GHCR, *.staging.wetfish.net)
- `k8s/overlays/prod/` - Prod overlay (GHCR, *.wetfish.net)
- `config/` - K8s-modified config files (nginx.conf, php.ini, etc.)
- `Dockerfile.*` - Container definitions (COPY paths reference `src/` subdir)

Base manifests use placeholder image names (e.g., `WIKI_NGINX_IMAGE:latest`) that Kustomize `images` transformers replace per environment. Overlays set namespace, images, TLS/ingress hostnames, and env-specific values (SITE_URL, storageClassName).

### Infrastructure
- **Cluster**: k3d with built-in Traefik disabled (`--k3s-arg '--disable=traefik'`); custom Traefik v2.11 deployed via raw manifests in `infrastructure/traefik/`
- **Ports**: HTTP 8080 -> 80, HTTPS 8443 -> 443 on the load balancer
- **Registry**: Local k3d registry on port 5000 for dev; GHCR (`ghcr.io/cybaxx/web-services-k8s`) for CI/CD
- **Storage**: k3d local-path storage class (dev only, set via overlay)
- **DNS**: Requires `/etc/hosts` entries managed by `scripts/setup-hosts.sh`

### Deploy Script Behavior
`scripts/deploy.sh` uses `kubectl apply -k` with Kustomize overlays from `services/<name>/k8s/overlays/<env>/`. Accepts `--env dev|staging|prod` flag (default: dev). For `monitoring` and `traefik` services, it uses Helm with values from `monitoring/values/`. Backward-compatible with old `./scripts/deploy.sh wetfish-dev wiki` syntax.

### Wiki Service (Pilot)
- **Stack**: Custom PHP application (in `src/wwwroot/`) - NOT MediaWiki
- **Architecture**: Nginx and PHP-FPM run as sidecar containers in the same pod (`wiki-web` deployment)
- **Database**: MariaDB 10.10 (`wiki-mysql` deployment)
- **Images (dev)**: `wetfish-registry:5000/wiki:nginx` and `:php` (local k3d registry)
- **Images (CI/CD)**: `ghcr.io/cybaxx/web-services-k8s/wiki:staging-nginx` / `:prod-nginx` etc.
- **ConfigMaps**: nginx.conf, php.ini, php-fpm-pool.conf in `k8s/base/configmap.yaml`
- **Storage**: PVCs for wwwroot (2Gi) and uploads (5Gi)
- **Access**: `http://wiki.wetfish.local` (dev, requires /etc/hosts entry)

### Monitoring Stack
Deployed via Helm charts in `wetfish-monitoring` namespace with custom values in `monitoring/values/`:

| Helm Release | Chart | Purpose | Access |
|-------------|-------|---------|--------|
| `prometheus` | kube-prometheus-stack | Prometheus + Grafana + Alertmanager + node-exporter + kube-state-metrics | `grafana.wetfish.local:8080` (admin/admin) |
| `loki` | grafana/loki | Log aggregation (SingleBinary mode, filesystem storage) | Internal only |
| `tempo` | grafana/tempo | Distributed tracing (OTLP receiver) | Internal only |
| `promtail` | grafana/promtail | Log collector DaemonSet shipping to Loki | Internal only |

Grafana has 4 pre-configured datasources: Prometheus (default), Alertmanager, Loki, Tempo.
Wiki service has ServiceMonitors (`wiki-web-metrics`, `wiki-mysql-metrics`) for Prometheus discovery.

## Git Workflow

```
feature/branch -> PR -> main -> (merge to release for prod)
```

### CI/CD
Reusable workflow pattern: `.github/workflows/build-service.yml` (workflow_call) handles checkout, GHCR login, metadata tagging, and docker build+push. Per-service trigger workflows call it:

| Workflow | Service | Components | Triggers |
|----------|---------|------------|----------|
| `build-wiki.yml` | wiki | nginx, php | `services/wiki/**` |
| `build-home.yml` | home | app | `services/home/**` |
| `build-glitch.yml` | glitch | nginx, php | `services/glitch/**` |
| `build-click.yml` | click | nginx, php | `services/click/**` |
| `build-danger.yml` | danger | nginx, php | `services/danger/**` |

Image tags: `staging-<component>` on push to `main`, `prod-<component>` on push to `release`, plus branch/sha/pr tags.

### Submodules
Service source code lives in git submodules under `services/<name>/src/`, pointing to upstream wetfish repos on the `release` branch:
- `services/wiki/src` → `https://github.com/wetfish/wiki.git`
- `services/home/src` → `https://github.com/wetfish/wetfish.net`
- `services/glitch/src` → `https://github.com/wetfish/glitch.git`
- `services/click/src` → `https://github.com/wetfish/click.git`
- `services/danger/src` → `https://github.com/wetfish/danger.git`

Clone with `git clone --recurse-submodules` or run `git submodule update --init` after cloning.
To update a submodule to latest upstream: `git -C services/<name>/src pull origin release`

## Documentation

Detailed docs live in `docs/`:
- `architecture-design.md` - System design, network architecture, sidecar pattern details
- `k3s-setup-guide.md` - Cluster prerequisites and setup
- `migration-strategy.md` - Four-phase migration plan with rollback procedures
- `monitoring-stack.md` - FishVision observability model configuration
- `troubleshooting.md` - Emergency commands and common issue resolution

## Important Conventions
- All scripts auto-detect PROJECT_DIR from their location (no hardcoded paths)
- K8s manifests use Kustomize base/overlay pattern (no more numbered flat files)
- Active GitHub Actions workflows are at repo root `.github/workflows/`; workflows use `submodules: true` in checkout
- Dev images go to local k3d registry (`localhost:5000`); Kustomize overlays map to `wetfish-registry:5000` (cluster-internal name)
- Service source code is in git submodules (`services/<name>/src/`); Dockerfiles COPY from `src/` subdirectory
- Secrets are generated per-overlay via `scripts/generate-secrets.sh --env <env>` and gitignored
