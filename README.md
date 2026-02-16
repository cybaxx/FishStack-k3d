# Wetfish Web-Services K8s

Kubernetes migration of wetfish web-services with observability stack (Prometheus, Grafana, Loki, Tempo).

---

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                      k3d Cluster                            │
├─────────────────────────────────────────────────────────────┤
│  wetfish-system    │  wetfish-dev      │ wetfish-monitoring │
│  (Traefik)         │  (Services)       │  (Observability)   │
│                    │  ├─ Wiki          │  ├─ Prometheus     │
│                    │  ├─ Home          │  ├─ Grafana        │
│                    │  ├─ Glitch        │  ├─ Loki           │
│                    │  ├─ Click         │  ├─ Tempo          │
│                    │  └─ Danger        │  └─ AlertManager   │
└─────────────────────────────────────────────────────────────┘
```

### Services

| Service | Stack | Database | Status |
|---------|-------|----------|--------|
| **wiki** | PHP 8.2 + nginx (sidecar) | MariaDB 10.10 | Running |
| **home** | SvelteKit (static nginx) | None | Running |
| **glitch** | PHP 5.6 + nginx (sidecar) | None | Running |
| **click** | PHP 5.6 + nginx (sidecar) | MariaDB 10.10 | Running |
| **danger** | PHP 5.6 + nginx (sidecar) | MariaDB 10.10 | Running |
| **forum** | SMF 2.1.6 + PHP 8.4 | MariaDB | Deferred |

---

## Quick Start

### Prerequisites
- Docker Desktop or Docker Engine
- k3d
- kubectl
- helm

### 1. Setup Development Environment
```bash
git clone git@github.com:cybaxx/web-services-k8s.git
cd web-services-k8s

# Create k3d cluster with local registry
./scripts/setup-dev.sh

# Add DNS entries to /etc/hosts
sudo ./scripts/setup-hosts.sh
```

### 2. Build and Push Images
```bash
# Wiki (PHP 8.2)
docker build -t localhost:5000/wiki:nginx -f services/wiki/Dockerfile.nginx services/wiki/
docker build -t localhost:5000/wiki:php -f services/wiki/Dockerfile.php services/wiki/
docker push localhost:5000/wiki:nginx && docker push localhost:5000/wiki:php

# Home (static SvelteKit)
docker build -t localhost:5000/home:latest services/home/
docker push localhost:5000/home:latest

# Glitch (PHP 5.6)
docker build -f services/glitch/Dockerfile.nginx -t localhost:5000/glitch:nginx services/glitch/
docker build -f services/glitch/Dockerfile.php -t localhost:5000/glitch:php services/glitch/
docker push localhost:5000/glitch:nginx && docker push localhost:5000/glitch:php

# Click (PHP 5.6)
docker build -f services/click/Dockerfile.nginx -t localhost:5000/click:nginx services/click/
docker build -f services/click/Dockerfile.php -t localhost:5000/click:php services/click/
docker push localhost:5000/click:nginx && docker push localhost:5000/click:php

# Danger (PHP 5.6)
docker build -f services/danger/Dockerfile.nginx -t localhost:5000/danger:nginx services/danger/
docker build -f services/danger/Dockerfile.php -t localhost:5000/danger:php services/danger/
docker push localhost:5000/danger:nginx && docker push localhost:5000/danger:php
```

### 3. Deploy Services
```bash
# Deploy all services
./scripts/deploy.sh wetfish-dev wiki
./scripts/deploy.sh wetfish-dev home
./scripts/deploy.sh wetfish-dev glitch
./scripts/deploy.sh wetfish-dev click
./scripts/deploy.sh wetfish-dev danger

# Load database schemas (first deploy only)
kubectl exec -i deployment/wiki-mysql -n wetfish-dev -- mysql -uroot -pwikipass wikidb < services/wiki/config/schema.sql
kubectl exec -i deployment/click-mysql -n wetfish-dev -- mysql -uroot -pclickpass clickdb < services/click/schema.sql
kubectl exec -i deployment/danger-mysql -n wetfish-dev -- mysql -uroot -pdangerpass dangerdb < services/danger/schema.sql
```

### 4. Access Services
```
http://wiki.wetfish.local:8080
http://home.wetfish.local:8080
http://glitch.wetfish.local:8080
http://click.wetfish.local:8080
http://danger.wetfish.local:8080
```

---

## Development Commands

### Cluster Lifecycle
```bash
./scripts/setup-dev.sh          # Create k3d cluster
./scripts/cleanup.sh            # Tear down cluster
sudo ./scripts/setup-hosts.sh   # Manage /etc/hosts entries
k3d cluster start wetfish-dev   # Start existing cluster
k3d cluster stop wetfish-dev    # Stop cluster
```

### Deploying
```bash
./scripts/deploy.sh <namespace> <service> [action]
./scripts/deploy.sh wetfish-dev wiki              # Deploy wiki
./scripts/deploy.sh wetfish-dev wiki delete        # Remove wiki
./scripts/deploy.sh wetfish-monitoring monitoring  # Deploy monitoring (Helm)
./scripts/deploy.sh wetfish-system traefik         # Deploy Traefik
```

### Debugging
```bash
# Health checks
./scripts/test-deployment.sh wetfish-dev wiki

# Pods and logs (sidecar containers: nginx + php-fpm)
kubectl get pods -n wetfish-dev
kubectl logs deployment/wiki-web -n wetfish-dev -c nginx -f
kubectl logs deployment/wiki-web -n wetfish-dev -c php-fpm -f

# Shell access
kubectl exec -it deployment/wiki-web -n wetfish-dev -c php-fpm -- bash
```

---

## Project Structure

```
web-services-k8s/
├── .github/workflows/      # CI/CD pipelines (GitHub Actions)
├── services/               # Application services
│   ├── wiki/               # Wiki (PHP 8.2 custom app + MariaDB)
│   ├── home/               # Home (SvelteKit static site)
│   ├── glitch/             # Glitch (PHP 5.6 + Node 14)
│   ├── click/              # Click (PHP 5.6 + MariaDB)
│   └── danger/             # Danger (PHP 5.6 + MariaDB)
├── infrastructure/         # Core infrastructure
│   └── traefik/            # Traefik v2.11 ingress controller
├── monitoring/             # Observability stack
│   └── values/             # Helm values (Prometheus, Loki, Tempo)
├── scripts/                # Automation scripts
└── docs/                   # Documentation
```

Each service has `k8s/` manifests (applied in numbered order), `Dockerfile.*` container definitions, and `config/` application configs.

---

## CI/CD

GitHub Actions workflows in `.github/workflows/` build container images to GHCR on push to main. Workflows trigger on changes to their respective `services/<name>/**` paths.

```
feature/branch -> PR -> main
```

---

## Roadmap

### Phase 1: Foundation (complete)
- [x] k3d cluster with Traefik ingress
- [x] Wiki service (pilot migration)
- [x] Home, glitch, click, danger services
- [x] CI/CD workflows
- [x] Monitoring Helm values

### Phase 2: Production Ready
- [ ] Production cluster configuration
- [ ] Security hardening (see `docs/security-audit-action-items.md`)
- [ ] Backup strategies
- [ ] TLS/HTTPS enforcement

### Phase 3: Scale Out
- [ ] Forum service (SMF 2.1.6)
- [ ] Multi-environment support
- [ ] GitOps (ArgoCD)
