# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Kubernetes migration of wetfish web-services from Docker Compose to a k3d cluster with full observability (Prometheus, Grafana, Loki, Tempo). Currently in foundation phase with the wiki (custom PHP application) service as the pilot migration.

## Key Commands

### Cluster Lifecycle
```bash
./scripts/setup-dev.sh          # Create k3d cluster (1 server, 2 agents, local registry on :5000)
./scripts/cleanup.sh            # Tear down cluster and Docker resources
sudo ./scripts/setup-hosts.sh   # Add service DNS entries to /etc/hosts
k3d cluster start wetfish-dev   # Start existing cluster
k3d cluster stop wetfish-dev    # Stop cluster
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
kubectl logs deployment/wiki-web -n wetfish-dev -f
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
- **Cluster**: k3d with built-in Traefik disabled (`--k3s-arg '--disable=traefik'`); custom Traefik v2.11 deployed separately
- **Ports**: HTTP 8080 -> 80, HTTPS 8443 -> 443 on the load balancer
- **Registry**: Local k3d registry on port 5000 for dev; GHCR (`ghcr.io/cybaxx/web-services-k8s`) for CI/CD
- **Storage**: k3d local-path storage class (dev only)
- **DNS**: Requires `/etc/hosts` entries (e.g., `127.0.0.1 wiki.wetfish.local`)

### Deploy Script Behavior
`scripts/deploy.sh` applies manifests from `services/<name>/k8s/*.yaml` in alphabetical order, waits for rollout (300s timeout), then shows status. For `monitoring` and `traefik` services, it uses Helm instead of raw manifests.

### Wiki Service (Pilot)
- **Stack**: Custom PHP application with nginx + php-fpm sidecar + MariaDB 10.10
- **Architecture**: Nginx and PHP-FPM run as sidecar containers in the same pod
- **Images**: `ghcr.io/cybaxx/web-services-k8s/wiki:latest-nginx` and `:latest-php`
- **Storage**: PVCs for wwwroot (2Gi) and uploads (5Gi)
- **Access**: `http://wiki.wetfish.local` (requires /etc/hosts entry)

## Git Workflow

```
feature/branch -> PR -> dev-init-1 -> main
```

CI/CD via GitHub Actions builds container images to GHCR with branch-based + SHA tags.

## Documentation

Detailed docs live in `docs/`:
- `architecture-design.md` - System design, network architecture, data flow
- `k3s-setup-guide.md` - Cluster prerequisites and setup
- `migration-strategy.md` - Four-phase migration plan with rollback procedures
- `monitoring-stack.md` - FishVision observability model configuration
- `troubleshooting.md` - Emergency commands and common issue resolution
