# Architecture Design

Kubernetes architecture for the wetfish web-services migration with multi-environment support and full observability.

---

## High-Level Design

```
                         k3d Cluster (wetfish-dev)
+------------------------------------------------------------------------+
| wetfish-system     | wetfish-dev        | wetfish-monitoring            |
| (Infrastructure)   | (Applications)     | (Observability)               |
| - Traefik Ingress  | - Wiki             | - Prometheus + Grafana        |
| - Cert-Manager     | - Home             | - Alertmanager                |
|                    | - Glitch           | - Loki + Promtail             |
|                    | - Click            | - Tempo                       |
|                    | - Danger           |                               |
+------------------------------------------------------------------------+
| wetfish-staging    | wetfish-prod       |                               |
| (Staging apps)     | (Production apps)  |                               |
+------------------------------------------------------------------------+
```

---

## Network Architecture

```
Browser -> localhost:8080 -> k3d Load Balancer -> Traefik -> Ingress -> Service -> Pod

Dev Routes:
  wiki.wetfish.local      -> wetfish-dev/wiki-web
  home.wetfish.local      -> wetfish-dev/home
  glitch.wetfish.local    -> wetfish-dev/glitch-web
  click.wetfish.local     -> wetfish-dev/click-web
  danger.wetfish.local    -> wetfish-dev/danger-web
  grafana.wetfish.local   -> wetfish-monitoring/prometheus-grafana
  prometheus.wetfish.local -> wetfish-monitoring/prometheus-kube-prometheus-prometheus
  alertmanager.wetfish.local -> wetfish-monitoring/prometheus-kube-prometheus-alertmanager
```

---

## Namespace Architecture

### wetfish-system
Core infrastructure components:
- Traefik v3.5 Ingress Controller (deployed by k3d, watches all namespaces)
- Cert-Manager (Helm, self-signed ClusterIssuer for dev)

### wetfish-dev
Development application services:
- **Wiki** - Custom PHP 8.2 + nginx sidecar + MariaDB 10.10
- **Home** - SvelteKit static site served by nginx (single container)
- **Glitch** - PHP 5.6 + nginx sidecar (no database)
- **Click** - PHP 5.6 + nginx sidecar + MariaDB 10.10
- **Danger** - PHP 5.6 + nginx sidecar + MariaDB 10.10

### wetfish-staging / wetfish-prod
Same services, different image tags and hostnames (via Kustomize overlays).

### wetfish-monitoring
Observability stack (all deployed via Helm):
- Prometheus (metrics collection, ServiceMonitor discovery)
- Grafana (visualization, pre-configured datasources)
- Alertmanager (alert routing)
- Loki (log aggregation, SingleBinary mode)
- Tempo (distributed tracing)
- Promtail (log collector DaemonSet)
- Node Exporter + Kube State Metrics

---

## Service Architecture

### Sidecar Pattern (Wiki, Click, Danger, Glitch)

```
Pod: <service>-web
+----------------------------+
| Init Container             |
| (copies src to shared vol) |
+----------------------------+
| Container: nginx           | <- serves static files, proxies PHP to fpm
| Container: php-fpm         | <- runs PHP application
+----------------------------+
| Shared Volume: wwwroot     |
+----------------------------+
```

### Single Container Pattern (Home)

```
Pod: home
+----------------------------+
| Container: nginx           | <- serves pre-built SvelteKit static files
+----------------------------+
```

### Database Pattern (Wiki, Click, Danger)

```
Deployment: <service>-mysql
+----------------------------+
| Container: mariadb:10.10   |
| Strategy: Recreate         | <- required for RWO PVC
| PVC: <service>-mysql-pvc   |
+----------------------------+
```

---

## Kustomize Structure

Each service uses base + overlays:

```
services/<name>/k8s/
  base/
    kustomization.yaml      # Lists all base resources
    configmap.yaml          # nginx.conf, php.ini (services with configs)
    mysql.yaml              # DB Deployment + Service + PVC (wiki, click, danger)
    mysql-config.yaml       # DB ConfigMap (wiki, click, danger)
    web.yaml                # Web Deployment + Service + PVCs
    ingress.yaml            # Ingress with placeholder host
    monitoring.yaml         # ServiceMonitors (wiki only currently)
  overlays/
    dev/                    # namespace: wetfish-dev, local registry, *.wetfish.local
    staging/                # namespace: wetfish-staging, GHCR, *.staging.wetfish.net
    prod/                   # namespace: wetfish-prod, GHCR, *.wetfish.net
```

Base manifests use placeholder image names (e.g., `WIKI_NGINX_IMAGE:latest`) replaced by Kustomize `images` transformers. Overlays set namespace, images, TLS/ingress hostnames, `SITE_URL`, and `storageClassName`.

---

## Environments

| Environment | Namespace | Hostnames | Registry | Branch | TLS Issuer |
|-------------|-----------|-----------|----------|--------|------------|
| dev | wetfish-dev | `*.wetfish.local` | `wetfish-registry:5000` (k3d local) | local builds | `wetfish-selfsigned` |
| staging | wetfish-staging | `*.staging.wetfish.net` | `ghcr.io/cybaxx/web-services-k8s` | `main` | `wetfish-letsencrypt` |
| prod | wetfish-prod | `*.wetfish.net` | `ghcr.io/cybaxx/web-services-k8s` | `release` | `wetfish-letsencrypt` |

---

## CI/CD Pipeline

```
Push to main/release -> GitHub Actions -> Build Docker images -> Push to GHCR
                                       -> Tag: staging-<component> (main)
                                       -> Tag: prod-<component> (release)
```

Reusable workflow pattern (`.github/workflows/build-service.yml`) called by per-service trigger workflows. Each triggers on path changes under `services/<name>/**`.

---

## Monitoring Architecture

```
                    Prometheus
                   /    |     \
        scrapes   /     |      \  scrapes
                 /      |       \
  Node Exporter   kube-state   ServiceMonitors
                  -metrics     (wiki-web, wiki-mysql)
                        |
                   Alertmanager
                        |
                     Grafana  <--- Loki  <--- Promtail (DaemonSet)
                        |
                      Tempo  <--- OTLP (future app instrumentation)
```

Prometheus discovers ServiceMonitors across all namespaces. Promtail ships container logs from all nodes to Loki. Grafana has all datasources pre-configured.

---

## Infrastructure Components

### Traefik Ingress Controller
- Deployed by k3d (v3.5, Helm chart in kube-system)
- Watches Ingress resources across all namespaces
- HTTP(8080) and HTTPS(8443) ports exposed via k3d load balancer

### Cert-Manager
- Deployed via Helm into `cert-manager` namespace
- Self-signed ClusterIssuer (`wetfish-selfsigned`) for dev
- Let's Encrypt ClusterIssuer (`wetfish-letsencrypt`) for staging/prod

### Local Registry
- k3d-managed registry on port 5000
- External: `localhost:5000` (for `docker push`)
- In-cluster: `wetfish-registry:5000` (for Kubernetes image pulls)

### Storage
- `local-path` StorageClass (k3d/k3s built-in, dev only)
- Set via Kustomize overlay env-patch (not hardcoded in base)

---

## Database Architecture

| Service | Engine | Character Set | Collation | Storage |
|---------|--------|--------------|-----------|---------|
| Wiki | MariaDB 10.10 | utf8mb4 | utf8mb4_general_ci | 2Gi PVC |
| Click | MariaDB 10.10 | latin1 | latin1_swedish_ci | 2Gi PVC |
| Danger | MariaDB 10.10 | utf8 | utf8_general_ci | 2Gi PVC |

All MySQL deployments use `strategy: Recreate` (required for RWO PVCs). `sql_mode = ""` set for legacy PHP compatibility.

---

## Architecture Decisions

| Decision | Rationale |
|----------|-----------|
| k3d for dev | Docker-native, low overhead, built-in registry and load balancer |
| Kustomize over Helm for apps | Simpler for static PHP apps, overlays match env model well |
| Helm for monitoring | Complex charts with many CRDs, community-maintained values |
| Sidecar pattern | nginx + php-fpm need shared filesystem, single pod simplifies networking |
| Traefik (k3d default) | Already integrated, watches all namespaces, no extra config needed |
| php:5.6-fpm-alpine | Only working PHP 5.6 image (Sury/Debian repos broken for 5.6) |
| Recreate strategy for MySQL | RWO PVC deadlock prevention (new pod can't mount until old releases) |
