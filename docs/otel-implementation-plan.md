# OpenTelemetry Implementation Plan

Instruments all wetfish services (wiki, home, glitch, click, danger, forum) for logs, metrics, and traces. **FishVision on dedi-prod is the monitoring source of truth** — Prometheus scrapes, alert rules, and Grafana dashboards all live there.

## Architecture

```
FishStack-k3d cluster (staging/prod node)
├── wetfish-system/traefik     → :8082/metrics  ←─┐
├── wetfish-prod/wiki-web      → :9113 (nginx)  ←─┤
│                              → :9253 (phpfpm) ←─┤  FishVision (dedi-prod)
├── wetfish-prod/wiki-mysql    → :9104 (mysql)  ←─┤  prometheus.yml static_configs
├── wetfish-prod/click-web     → :9113 / :9253  ←─┤
├── wetfish-prod/danger-web    → :9113 / :9253  ←─┤
└── ...                                          ←─┘

Logs: Promtail DaemonSet in cluster → FishVision Loki (dedi-prod:3100)
Traces: wiki PHP → OTLP → FishVision Tempo (dedi-prod:4318)
```

No prometheus-operator, no ServiceMonitors, no in-cluster Prometheus.

---

## Current State

| Component | Status |
|-----------|--------|
| Traefik metrics `:8082` | Exposed + scraped by FishVision |
| Traefik access logs | JSON format enabled |
| Promtail (in-cluster) | Not deployed |
| nginx JSON logs | Not configured |
| nginx-exporter sidecars | Not deployed |
| php-fpm-exporter sidecars | Not deployed |
| mysql-exporter sidecars | Not deployed |
| Wiki OTEL traces | Not deployed |
| FishVision scrape targets | Traefik only |
| FishVision dashboards | factory + andon-alert + web-services (no k8s services dashboard yet) |

---

## Scope

| Signal | Wiki (PHP 8.2) | Home (static) | Glitch / Click / Danger (PHP 5.6) | Forum (PHP 8.4) |
|--------|---------------|---------------|-----------------------------------|-----------------|
| Logs | JSON nginx + php-fpm | JSON nginx | JSON nginx + php-fpm | JSON nginx + php-fpm |
| Metrics | nginx + phpfpm + mysql exporters | nginx exporter | nginx + phpfpm + mysql exporters | nginx + phpfpm + mysql exporters |
| Traces | OTEL PHP SDK (auto) | None (static) | Out of scope (PHP 5.6) | Candidate (Phase 3+) |

---

## Phase 1 — Structured Logging

Promtail will collect logs from every pod. Structured JSON makes them queryable in Loki without fragile regex parsing.

### 1.1 Nginx JSON Log Format

Add to each service's nginx ConfigMap:

```nginx
log_format json_access escape=json '{'
  '"time":"$time_iso8601",'
  '"remote_addr":"$remote_addr",'
  '"method":"$request_method",'
  '"uri":"$uri",'
  '"status":$status,'
  '"bytes_sent":$bytes_sent,'
  '"request_time":$request_time,'
  '"upstream_response_time":"$upstream_response_time",'
  '"user_agent":"$http_user_agent",'
  '"service":"<SERVICE_NAME>"'
'}';

access_log /dev/stdout json_access;
error_log  /dev/stderr warn;
```

**Files to update:**
- `services/wiki/k8s/base/configmap.yaml`
- `services/home/k8s/base/configmap.yaml`
- `services/glitch/k8s/base/configmap.yaml`
- `services/click/k8s/base/configmap.yaml`
- `services/danger/k8s/base/configmap.yaml`
- `services/forum/k8s/base/configmap.yaml`

### 1.2 PHP-FPM Log Cleanup

Add to each service's php-fpm pool config to remove the `NOTICE: child` prefix:

```ini
catch_workers_output = yes
decorate_workers_output = no
```

### 1.3 Promtail DaemonSet (in-cluster)

Deploy a lightweight Promtail DaemonSet that ships pod logs to FishVision's Loki on dedi-prod. This lives in `infrastructure/promtail/` (not a Helm chart — raw manifests matching FishVision's style).

Key config:

```yaml
clients:
  - url: http://<dedi-prod-ip>:3100/loki/api/v1/push

scrape_configs:
  - job_name: kubernetes-pods
    kubernetes_sd_configs:
      - role: pod
    pipeline_stages:
      - json:
          expressions:
            status: status
            method: method
            service: service
      - labels:
          status:
          method:
          service:
    relabel_configs:
      - action: labelmap
        regex: __meta_kubernetes_pod_label_(.+)
      - source_labels: [__meta_kubernetes_namespace]
        target_label: namespace
      - source_labels: [__meta_kubernetes_pod_name]
        target_label: pod
      - source_labels: [__meta_kubernetes_pod_container_name]
        target_label: container
      - replacement: /var/log/pods/*$1*/*/*.log
        source_labels: [__meta_kubernetes_pod_uid]
        target_label: __path__
```

**Files to create:**
- `infrastructure/promtail/serviceaccount.yaml` — ClusterRole with pod/node list+watch
- `infrastructure/promtail/configmap.yaml` — promtail config pointing at dedi-prod Loki
- `infrastructure/promtail/daemonset.yaml` — mounts `/var/log` and `/var/lib/docker/containers`

Apply with `kubectl apply -f infrastructure/promtail/` (same pattern as Traefik).

---

## Phase 2 — Metrics Coverage

Exporters run as sidecars and expose `/metrics` on fixed ports. FishVision's prometheus.yml adds static scrape targets pointing at the staging/prod node IP + NodePort for each exporter.

### 2.1 Nginx Exporter Sidecar

Add `stub_status` location to each service's nginx config:

```nginx
location /nginx_status {
  stub_status;
  allow 127.0.0.1;
  deny all;
}
```

Add sidecar to each web Deployment:

```yaml
- name: nginx-exporter
  image: nginx/nginx-prometheus-exporter:1.4.2
  args:
    - --nginx.scrape-uri=http://127.0.0.1:80/nginx_status
  ports:
    - name: metrics
      containerPort: 9113
  resources:
    requests: { cpu: 10m, memory: 16Mi }
    limits: { cpu: 50m, memory: 32Mi }
```

Expose port 9113 on the Service with `type: NodePort` (or use a dedicated metrics Service).

**Services:** wiki, home, glitch, click, danger, forum

### 2.2 PHP-FPM Exporter Sidecar

Enable the status page in each PHP service's pool config:

```ini
pm.status_path = /status
```

Add sidecar:

```yaml
- name: phpfpm-exporter
  image: hipages/php-fpm_exporter:2.2.0
  args:
    - --phpfpm.scrape-uri=tcp://127.0.0.1:9000/status
  ports:
    - name: phpfpm-metrics
      containerPort: 9253
  resources:
    requests: { cpu: 10m, memory: 16Mi }
    limits: { cpu: 50m, memory: 32Mi }
```

**Services:** wiki, glitch, click, danger, forum (not home — static site)

### 2.3 MySQL Exporter Sidecar

Wiki already has one. Add to click and danger (and forum):

```yaml
- name: mysql-exporter
  image: prom/mysqld-exporter:v0.15.1
  env:
    - name: DATA_SOURCE_NAME
      value: "root:$(MYSQL_ROOT_PASSWORD)@(127.0.0.1:3306)/"
  ports:
    - name: mysql-metrics
      containerPort: 9104
  resources:
    requests: { cpu: 10m, memory: 16Mi }
    limits: { cpu: 50m, memory: 32Mi }
```

**Services:** click, danger, forum mysql Deployments

### 2.4 FishVision prometheus.yml — Add K8s Scrape Targets

Add scrape jobs to `FishVision/prometheus/prometheus.yml` for each exporter exposed via NodePort on the staging/prod node IPs. Pattern:

```yaml
- job_name: "fishstack-wiki-nginx"
  static_configs:
    - targets: ["<node-ip>:<nodeport>"]
      labels:
        environment: production
        project: web-services
        service: wiki

- job_name: "fishstack-wiki-phpfpm"
  static_configs:
    - targets: ["<node-ip>:<nodeport>"]
      labels:
        environment: production
        project: web-services
        service: wiki
```

NodePorts are assigned at deploy time — document them in `docs/nodeports.md` once established.

---

## Phase 3 — Wiki Traces (PHP 8.2)

### 3.1 Dockerfile.php

```dockerfile
RUN pecl install opentelemetry \
    && docker-php-ext-enable opentelemetry

COPY --from=composer:2 /usr/bin/composer /usr/bin/composer
RUN composer require \
      open-telemetry/sdk \
      open-telemetry/opentelemetry-auto-psr18 \
      open-telemetry/opentelemetry-auto-curl \
      --working-dir=/var/www
```

### 3.2 PHP INI (wiki ConfigMap)

```ini
extension=opentelemetry.so
OTEL_PHP_AUTOLOAD_ENABLED=true
OTEL_SERVICE_NAME=wiki
OTEL_TRACES_EXPORTER=otlp
OTEL_EXPORTER_OTLP_ENDPOINT=http://<dedi-prod-ip>:4318
OTEL_EXPORTER_OTLP_PROTOCOL=http/protobuf
OTEL_PROPAGATORS=tracecontext,baggage
```

### 3.3 Trace → Log Correlation

Add `trace_id` to the nginx JSON log format:

```nginx
'"trace_id":"$http_traceparent"'
```

Grafana Loki datasource derives Tempo trace links from this field.

---

## Phase 4 — FishVision Dashboard

Add a `web-services-k8s.json` Grafana dashboard to `FishVision/grafana/dashboards/` (alongside the existing `factory.json` and `web-services.json`).

### Panels per service row

| Panel | Source | Query |
|-------|--------|-------|
| Request rate | Prometheus | `rate(nginx_http_requests_total[5m])` by status |
| Error rate (5xx) | Prometheus | % 5xx |
| P95 response time | Prometheus | `histogram_quantile(0.95, rate(nginx_http_request_duration_seconds_bucket[5m]))` |
| Active PHP-FPM workers | Prometheus | `phpfpm_active_processes` |
| Log stream | Loki | `{namespace="wetfish-prod", app="wiki"}` |
| MySQL connections | Prometheus | `mysql_global_status_threads_connected` |

### Infrastructure row

Traefik request rate, error rate, P95 latency — already available via `traefik_router_*` metrics FishVision already scrapes.

---

## Implementation Order

```
Phase 1 — Logging
  1. Add JSON log_format to all nginx ConfigMaps
  2. Add decorate_workers_output=no to all php-fpm pool configs
  3. Create infrastructure/promtail/ raw manifests
  4. kubectl apply -f infrastructure/promtail/
  5. Redeploy all services

Phase 2 — Metrics
  6. Add stub_status to all nginx configs
  7. Add nginx-exporter sidecar to all web Deployments
  8. Add phpfpm status + exporter sidecar to PHP services
  9. Add mysql-exporter to click, danger, forum mysql Deployments
  10. Expose exporter ports as NodePorts
  11. Add scrape jobs to FishVision/prometheus/prometheus.yml
  12. Reload FishVision Prometheus (curl -X POST http://localhost:9090/-/reload)
  13. Redeploy all services

Phase 3 — Wiki Traces
  14. Update services/wiki/Dockerfile.php — OTEL extension + SDK
  15. Update wiki php.ini ConfigMap — OTEL env vars pointing at dedi-prod Tempo
  16. Add trace_id to wiki nginx log format
  17. Rebuild + redeploy wiki

Phase 4 — Dashboard
  18. Author FishVision/grafana/dashboards/web-services-k8s.json
  19. Reload FishVision Grafana
```

---

## Resource Impact

Additional sidecars per service pod (nginx + phpfpm + mysql where applicable):

| Sidecar | CPU req | Mem req |
|---------|---------|---------|
| nginx-exporter | 10m | 16Mi |
| phpfpm-exporter | 10m | 16Mi |
| mysql-exporter | 10m | 16Mi |

~150m CPU / ~240Mi memory total across all services — well within k3d agent capacity.
