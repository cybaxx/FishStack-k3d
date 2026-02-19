# Monitoring Stack

Observability stack for the wetfish k3d cluster, deployed via Helm charts into the `wetfish-monitoring` namespace.

---

## Architecture

```
                       wetfish-monitoring namespace
  +------------------------------------------------------------------+
  |  Prometheus  <-- scrapes -->  ServiceMonitors (all namespaces)    |
  |       |                                                          |
  |  Alertmanager  (alert routing)                                   |
  |       |                                                          |
  |  Grafana  ---- datasources ---> Prometheus, Loki, Tempo          |
  |                                                                  |
  |  Loki  <-- receives logs <-- Promtail (DaemonSet on all nodes)   |
  |                                                                  |
  |  Tempo  <-- receives traces (OTLP gRPC/HTTP)                    |
  +------------------------------------------------------------------+
```

**Data flow:**
- Metrics: Applications -> Prometheus (scrape) -> Grafana dashboards
- Logs: Container stdout/stderr -> Promtail (DaemonSet) -> Loki -> Grafana
- Traces: Applications -> OTLP -> Tempo -> Grafana

---

## Helm Releases

| Release | Chart | Version | Mode |
|---------|-------|---------|------|
| `prometheus` | `prometheus-community/kube-prometheus-stack` | 81.x | Full stack (Prometheus, Grafana, Alertmanager, node-exporter, kube-state-metrics, operator) |
| `loki` | `grafana/loki` | 6.x | SingleBinary (filesystem storage, no memcached) |
| `tempo` | `grafana/tempo` | 1.x | SingleBinary (local trace storage) |
| `promtail` | `grafana/promtail` | 6.x | DaemonSet (ships logs to Loki) |

---

## Configuration

Helm values live in `monitoring/values/`:

### prometheus-stack-values.yaml
- Dev-sized resources (Prometheus 512Mi, Grafana 128Mi)
- 7-day retention, 8GB storage cap
- `local-path` storageClass for PVCs (10Gi Prometheus, 2Gi Alertmanager, 2Gi Grafana)
- Discovers ServiceMonitors across all namespaces (`serviceMonitorSelectorNilUsesHelmValues: false`)
- Grafana has pre-configured `additionalDataSources` for Loki and Tempo
- Ingress enabled for Grafana, Prometheus, and Alertmanager via Traefik

### loki-values.yaml
- SingleBinary mode (`deploymentMode: SingleBinary`, `singleBinary.replicas: 1`)
- Filesystem storage with TSDB schema v13
- 72-hour retention
- Memcached caches disabled (overkill for dev)
- SimpleScalable/Distributed components zeroed out

### tempo-values.yaml
- SingleBinary mode with local trace storage
- 24-hour trace retention
- OTLP receivers on ports 4317 (gRPC) and 4318 (HTTP)

### promtail-values.yaml
- Ships logs to `http://loki.wetfish-monitoring.svc.cluster.local:3100/loki/api/v1/push`
- Lightweight resource footprint (64Mi request, 128Mi limit)

---

## Grafana Datasources

Grafana comes pre-configured with 4 datasources (all auto-provisioned):

| Datasource | Type | URL |
|-----------|------|-----|
| Prometheus | prometheus (default) | `http://prometheus-kube-prometheus-prometheus:9090/` |
| Alertmanager | alertmanager | `http://prometheus-kube-prometheus-alertmanager:9093/` |
| Loki | loki | `http://loki.wetfish-monitoring.svc.cluster.local:3100` |
| Tempo | tempo | `http://tempo.wetfish-monitoring.svc.cluster.local:3100` |

---

## ServiceMonitors

Wiki service has ServiceMonitors in `wetfish-dev` for Prometheus to discover:

- `wiki-web-metrics` - Monitors wiki-web service
- `wiki-mysql-metrics` - Monitors wiki-mysql service

These are defined in `services/wiki/k8s/base/monitoring.yaml` and deployed via Kustomize overlays.

---

## Access URLs (dev)

Requires `/etc/hosts` entries (managed by `scripts/setup-hosts.sh`):

| Service | URL | Credentials |
|---------|-----|-------------|
| Grafana | http://grafana.wetfish.local:8080 | admin / admin |
| Prometheus | http://prometheus.wetfish.local:8080 | - |
| Alertmanager | http://alertmanager.wetfish.local:8080 | - |

Or via port-forward:
```bash
kubectl port-forward svc/prometheus-grafana 3000:80 -n wetfish-monitoring
kubectl port-forward svc/prometheus-kube-prometheus-prometheus 9090:9090 -n wetfish-monitoring
kubectl port-forward svc/loki 3100:3100 -n wetfish-monitoring
```

---

## Deployment

### Deploy monitoring stack
```bash
./scripts/deploy.sh monitoring
# or as part of full stack:
./scripts/up.sh --with-monitoring
```

### Upgrade a release
```bash
helm upgrade prometheus prometheus-community/kube-prometheus-stack \
  --namespace wetfish-monitoring \
  --values monitoring/values/prometheus-stack-values.yaml \
  --wait --timeout 10m
```

### Check status
```bash
helm list -n wetfish-monitoring
kubectl get pods -n wetfish-monitoring
kubectl get servicemonitor -A
```

### Uninstall
```bash
helm uninstall promtail -n wetfish-monitoring
helm uninstall tempo -n wetfish-monitoring
helm uninstall loki -n wetfish-monitoring
helm uninstall prometheus -n wetfish-monitoring
```

---

## Troubleshooting

### No data in Grafana
```bash
# Check Prometheus targets
kubectl port-forward svc/prometheus-kube-prometheus-prometheus 9090:9090 -n wetfish-monitoring
# Visit http://localhost:9090/targets

# Check ServiceMonitors exist
kubectl get servicemonitor -A

# Check Loki is receiving logs
kubectl port-forward svc/loki 3100:3100 -n wetfish-monitoring
curl http://localhost:3100/loki/api/v1/labels
```

### Promtail not shipping logs
```bash
kubectl logs -l app.kubernetes.io/name=promtail -n wetfish-monitoring --tail=50
```

### Prometheus not scraping targets
```bash
# Verify ServiceMonitor labels match Prometheus selector
kubectl get prometheus -n wetfish-monitoring -o yaml | grep -A5 serviceMonitorSelector

# Prometheus discovers all ServiceMonitors (nil selector = match all)
# Re-apply service overlays to create ServiceMonitors:
kubectl apply -k services/wiki/k8s/overlays/dev/
```

---

## Resource Usage (dev)

Approximate resource footprint of the monitoring stack:

| Component | Pods | CPU Request | Memory Request |
|-----------|------|-------------|----------------|
| Prometheus | 1 | 200m | 512Mi |
| Grafana | 1 | 50m | 128Mi |
| Alertmanager | 1 | 50m | 128Mi |
| Prometheus Operator | 1 | 50m | 128Mi |
| Node Exporter | 3 (DaemonSet) | ~30m each | ~30Mi each |
| Kube State Metrics | 1 | ~10m | ~30Mi |
| Loki | 1 | 100m | 256Mi |
| Tempo | 1 | 50m | 128Mi |
| Promtail | 3 (DaemonSet) | ~50m each | ~64Mi each |
| **Total** | **~16** | **~800m** | **~1.7Gi** |
