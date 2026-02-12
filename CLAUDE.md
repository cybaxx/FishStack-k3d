# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Kubernetes migration of wetfish web-services from Docker Compose to a k3d cluster with full observability (Prometheus, Grafana, Loki, Tempo). Currently in Phase 1 (Foundation) with the wiki service as the pilot migration.

### Migration Phases
1. **Foundation (current)** - Wiki pilot, k3d cluster, CI/CD, monitoring stack
2. **Production Ready** - Production cluster, security hardening, backups
3. **Scale Out** - Remaining services (forum, home, danger, click), multi-env, GitOps

### Current Status
- Wiki service **running in k3d cluster** (verified: Traefik ingress routing works)
- GitHub Actions CI/CD workflows in place
- Infrastructure deployed (Traefik, namespaces)
- Monitoring Helm values created (not yet deployed to cluster)
- Scripts complete (setup, deploy, cleanup, hosts, testing)

### Known Issues & Lessons Learned
- Dockerfiles use Debian bookworm default packages (PHP 8.2, Node 18) - NodeSource/Sury repos removed (EOL/broken GPG keys)
- MySQL deployment uses `strategy: Recreate` (required for RWO PVCs)
- MySQL `sql_mode = ""` needed for legacy PHP code that passes `'NULL'` strings for auto-increment
- DB schema must be loaded manually on first deploy: `kubectl exec -i deployment/wiki-mysql -n wetfish-dev -- mysql -uroot -pwikipass wikidb < services/wiki/config/schema.sql`
- If k3d agent nodes show NotReady, restart them: `docker restart k3d-wetfish-dev-agent-0 k3d-wetfish-dev-agent-1`

## Key Commands

### Cluster Lifecycle
```bash
./scripts/setup-dev.sh          # Create k3d cluster (1 server, 2 agents, local registry on :5000)
./scripts/cleanup.sh            # Tear down cluster and Docker resources
sudo ./scripts/setup-hosts.sh   # Add service DNS entries to /etc/hosts
k3d cluster start wetfish-dev   # Start existing cluster
k3d cluster stop wetfish-dev    # Stop cluster
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
./scripts/deploy.sh <namespace> <service> [action]
# Examples:
./scripts/deploy.sh wetfish-dev wiki              # Deploy wiki
./scripts/deploy.sh wetfish-dev wiki delete        # Remove wiki
./scripts/deploy.sh wetfish-monitoring monitoring  # Deploy monitoring (Helm)
./scripts/deploy.sh wetfish-system traefik         # Deploy Traefik (Helm)
```

### Testing & Debugging
```bash
./scripts/test-deployment.sh wetfish-dev wiki  # Run health checks
kubectl get pods -n wetfish-dev
kubectl logs deployment/wiki-web -n wetfish-dev -c nginx -f
kubectl logs deployment/wiki-web -n wetfish-dev -c php-fpm -f
kubectl exec -it deployment/wiki-web -n wetfish-dev -c php-fpm -- bash
kubectl port-forward svc/grafana 3000:3000 -n wetfish-monitoring
```

## Architecture

### Namespaces
- **wetfish-system** - Infrastructure (Traefik ingress controller)
- **wetfish-dev** - Application services (wiki, future: forum, home, danger, click)
- **wetfish-monitoring** - Observability stack (Prometheus, Grafana, Loki, Tempo)

### Service Layout
Each service lives under `services/<name>/` with:
- `k8s/` - Kubernetes manifests, applied in numbered order (01-configmap, 02-secret, 03-mysql, etc.)
- `config/` - Application config files (nginx.conf, php.ini, etc.)
- `Dockerfile.*` - Container definitions
- `docker-compose*.yml` - Docker Compose variants (dev, staging, prod)

### Infrastructure
- **Cluster**: k3d with built-in Traefik disabled (`--k3s-arg '--disable=traefik'`); custom Traefik v2.11 deployed via raw manifests in `infrastructure/traefik/`
- **Ports**: HTTP 8080 -> 80, HTTPS 8443 -> 443 on the load balancer
- **Registry**: Local k3d registry on port 5000 for dev; GHCR (`ghcr.io/cybaxx/web-services-k8s`) for CI/CD
- **Storage**: k3d local-path storage class (dev only)
- **DNS**: Requires `/etc/hosts` entries managed by `scripts/setup-hosts.sh`

### Deploy Script Behavior
`scripts/deploy.sh` applies manifests from `services/<name>/k8s/*.yaml` in alphabetical order, waits for rollout (300s timeout), then shows status. For `monitoring` and `traefik` services, it uses Helm with values from `monitoring/values/`.

### Wiki Service (Pilot)
- **Stack**: Custom PHP application (in `wwwroot/`) - NOT MediaWiki
- **Architecture**: Nginx and PHP-FPM run as sidecar containers in the same pod (`wiki-web` deployment)
- **Database**: MariaDB 10.10 (`wiki-mysql` deployment)
- **Images (dev)**: `wetfish-registry:5000/wiki:nginx` and `:php` (local k3d registry)
- **Images (CI/CD)**: `ghcr.io/cybaxx/web-services-k8s/wiki:latest-nginx` and `:latest-php`
- **ConfigMaps**: nginx.conf, php.ini, php-fpm-pool.conf embedded in `k8s/01-configmap.yaml`
- **Storage**: PVCs for wwwroot (2Gi) and uploads (5Gi)
- **Access**: `http://wiki.wetfish.local` (requires /etc/hosts entry)

### Monitoring Stack
Deployed via Helm charts with custom values in `monitoring/values/`:
- `prometheus-stack-values.yaml` - kube-prometheus-stack (Prometheus + Grafana + Alertmanager)
- `loki-values.yaml` - Log aggregation
- `tempo-values.yaml` - Distributed tracing

## Git Workflow

```
feature/branch -> PR -> main
```

CI/CD via GitHub Actions (`.github/workflows/build-wiki-{nginx,php}.yml`) builds container images to GHCR on push to main. Workflows trigger on changes to `services/wiki/**`.

## Documentation

Detailed docs live in `docs/`:
- `architecture-design.md` - System design, network architecture, sidecar pattern details
- `k3s-setup-guide.md` - Cluster prerequisites and setup
- `migration-strategy.md` - Four-phase migration plan with rollback procedures
- `monitoring-stack.md` - FishVision observability model configuration
- `troubleshooting.md` - Emergency commands and common issue resolution

## Important Conventions
- All scripts auto-detect PROJECT_DIR from their location (no hardcoded paths)
- K8s manifests are numbered for ordered application (01-, 02-, etc.)
- Active GitHub Actions workflows are at repo root `.github/workflows/`; copies in `services/wiki/.github/workflows/` are the originals
- Dev images go to local k3d registry (`localhost:5000`); k8s manifests reference `wetfish-registry:5000` (cluster-internal name)
