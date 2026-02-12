# 🏗️ Architecture Design

> Kubernetes architecture design for wetfish web-services migration with complete observability stack.

---

## 🎯 Architecture Overview

### **High-Level Design**
```
┌─────────────────────────────────────────────────────────────────┐
│                    k3d Cluster Environment                      │
├─────────────────────────────────────────────────────────────────┤
│  wetfish-system   │  wetfish-dev  │ wetfish-monitoring          │
│  (Traefik)        │  (Services)   │  (Observability)            │
│  ├─ Ingress       │  ├─ Wiki      │  ├─ Prometheus              │
│  ├─ CertManager   │  ├─ Forum     │  ├─ Grafana                 │
│  └─ DNS           │  ├─ Home      │  ├─ Loki                    │
│                   │  ├─ Danger    │  ├─ Tempo                   │
│                   │  └─ Click     │  └─ AlertManager            │
└─────────────────────────────────────────────────────────────────┘
```

### **Migration Strategy**
```
Docker Compose → Kubernetes → Production K8s
      │              │              │
  Current State   Development    Target State
```

---

## 🌐 Network Architecture

### **Cluster Networking**
```
┌─────────────────────────────────────────────────────┐
│                  k3d Cluster                        │
├─────────────────────────────────────────────────────┤
│  Load Balancer (Port 8080/8443)                     │
│         │                                           │
│  ┌─────▼─────┐                                      │
│  │  Traefik  │ ← Ingress Controller                 │
│  │  Ingress  │   - HTTP/HTTPS termination           │
│  └─────┬─────┘   - SSL certificates                 │
│         │                                           │
│  ┌──────▼───────┐                                   │
│  │  Namespaces  │                                   │
│  ├─────────────┤                                    │
│  │ wetfish-dev │ ← Application Services             │
│  │ monitoring  │ ← Observability Stack              │
│  │ system      │ ← Core Infrastructure              │
│  └─────────────┘                                    │
└─────────────────────────────────────────────────────┘
```

### **Service Communication**
```
Internet → Cloudflare → k3d LoadBalancer → Traefik → Services

Internal Routes:
- wiki.wetfish.local → wetfish-dev/wiki-service
- forum.wetfish.local → wetfish-dev/forum-service
- grafana.wetfish.local → wetfish-monitoring/grafana
- prometheus.wetfish.local → wetfish-monitoring/prometheus
```

---

## 🏛️ Namespace Architecture

### **wetfish-system**
```yaml
Purpose: Core infrastructure components
Components:
  - Traefik Ingress Controller
  - Cert-Manager (future)
  - Cluster DNS configuration
  - Storage classes

Resources:
  - IngressClass: traefik
  - StorageClass: local-path
  - Network policies (future)
```

### **wetfish-monitoring**
```yaml
Purpose: Observability and alerting
Components:
  - Prometheus (metrics collection)
  - Grafana (visualization)
  - Loki (log aggregation)
  - Tempo (distributed tracing)
  - AlertManager (alert routing)

Resources:
  - ServiceMonitors: Application metrics
  - PrometheusRules: Alert definitions
  - Dashboards: Grafana visualizations
```

### **wetfish-dev**
```yaml
Purpose: Development applications
Components:
  - Wiki (Custom PHP app with nginx + php-fpm sidecar + MariaDB)
  - Forum (Node.js + PostgreSQL) - Future
  - Home (Static site) - Future
  - Danger (JavaScript sandbox) - Future
  - Click (Click tracking) - Future

Resources:
  - Deployments: Application containers (sidecar pattern)
  - Services: Internal communication
  - PersistentVolumes: Database storage, uploads, wwwroot
  - ConfigMaps: nginx.conf, php.ini, php-fpm pool config
  - Secrets: Database credentials, application passwords
```

---

## 📊 Data Flow Architecture

### **Application Flow**
```
┌──────────┐    HTTP/HTTPS     ┌──────────┐    Service  ┌──────────┐
│  User    │ ────────────────► │ Traefik  │ ───────────►│  Wiki    │
│ Request  │                   │ Ingress  │             │ Service  │
└──────────┘                   └────┬─────┘             └────┬─────┘
                                    │                        │
                               ┌───▼───────────────────────▼───┐
                               │        Metrics Export         │
                               └───────────┬───────────────────┘
                                           │
                                   ┌───────▼───────┐
                                   │   Prometheus  │
                                   │    Scrapes    │
                                   └───────┬───────┘
                                           │
                                   ┌───────▼───────┐
                                   │    Grafana    │
                                   │  Dashboards   │
                                   └───────────────┘
```

### **Logging Architecture**
```
Application → stdout/stderr → Docker → Fluent Bit → Loki → Grafana
```

### **Tracing Architecture**
```
Application → OpenTelemetry → Collector → Tempo → Grafana
```

---

## 🔧 Component Design

### **Ingress Controller (Traefik v2)**
```yaml
Configuration:
  - Docker provider for k3d
  - File provider for static routes
  - Cloudflare DNS integration
  - SSL certificate automation
  - Middleware for security

Features:
  - HTTP to HTTPS redirect
  - Path-based routing
  - Load balancing
  - Rate limiting (future)
  - IP whitelisting (Cloudflare)
```

### **Database Architecture**
```yaml
Services:
  Wiki:
    - MariaDB 10.10
    - PersistentVolume: 10GB
    - Backup: Daily snapshots
  
  Forum:
    - PostgreSQL 15
    - PersistentVolume: 5GB
    - Backup: Daily snapshots

Storage Strategy:
  - LocalPath provisioner (development)
  - NFS mounts (production planning)
  - Automated backup to cloud storage
```

### **Application Containers**
```yaml
Wiki Service:
  - MediaWiki: latest stable
  - PHP: 8.1-FPM
  - Nginx: Alpine
  - Extensions: Semantic MediaWiki, etc.
  
Forum Service:
  - Node.js: 18 LTS
  - Express.js framework
  - Redis for caching
```

---

## 📈 Monitoring Architecture

### **Metrics Collection**
```
Applications → Prometheus Exporters → Scrape → Storage → Query → Grafana
             ↑                      ↑
         ServiceMonitors     PrometheusOperator
```

### **Alert Management**
```
Prometheus Rules → AlertManager → Routes → IRC/Webhook → Notifications
```

### **Dashboard Architecture**
```
Grafana Dashboards:
├── Cluster Overview
│   ├── Node Health
│   ├── Resource Usage
│   └── Network Performance
├── Application Metrics
│   ├── Wiki Performance
│   ├── Database Health
│   └── User Activity
└── System Monitoring
    ├── Container Resources
    ├── Log Analysis
    └── Alert Status
```

---

## 🚀 Deployment Architecture

### **CI/CD Pipeline**
```
GitHub Repository → GitHub Actions → Container Build → GHCR Push → k3d Deploy
                                    │              │             │
                            ┌───────▼───────┐ ┌────▼────┐ ┌──────▼──────┐
                            │  Build/Test   │ │ Registry│ │  Deploy     │
                            │  Lint/Scan    │ │ Push    │ │  Verify     │
                            └───────────────┘ └─────────┘ └─────────────┘
```

### **Environment Strategy**
```
Development (k3d) → Staging (k3s) → Production (k3s on cloud)
      │                    │                    │
  Local testing      Pre-production    Production services
  Rapid iteration   Integration tests  High availability
```

---

## 🔐 Security Architecture

### **Network Security**
```yaml
Development:
  - Cluster isolation (local only)
  - Basic network policies
  - Default deny (future)

Production Planning:
  - Namespace isolation
  - Service mesh (Istio)
  - Egress filtering
  - Ingress security
```

### **Secret Management**
```yaml
Development:
  - K8s secrets (base64)
  - Environment files
  - Local development

Production Planning:
  - External secret store
  - Sealed secrets
  - Automatic rotation
  - Audit logging
```

---

## 📁 Service Architecture Details

### **Wiki Service (MediaWiki)**
```yaml
Architecture:
  Frontend: Nginx (Alpine)
  Backend: PHP-FPM 8.1
  Database: MariaDB 10.10
  Cache: Redis (optional)
  Storage: 10GB PersistentVolume

Configuration:
  ConfigMap: MediaWiki settings
  Secret: Database credentials
  PVC: File storage
  Service: Internal HTTP

Dependencies:
  - Database connection
  - File storage access
  - External API access (for extensions)
```

### **Traefik Ingress**
```yaml
Configuration:
  Static config: Entrypoints, providers
  Dynamic config: Routers, services, middleware
  Storage: ConfigMaps, secrets
  Networking: LoadBalancer service

Features:
  - SSL termination
  - Path routing
  - Load balancing
  - Health checks
  - Metrics export
```

---

## 🎛️ Configuration Management

### **Environment Variables**
```yaml
Categories:
  - Database credentials (Secret)
  - External API keys (Secret)
  - Service URLs (ConfigMap)
  - Feature flags (ConfigMap)
  - Resource limits (Deployment)
```

### **Resource Allocation**
```yaml
Development Cluster:
  Wiki Service: 512MB RAM, 0.5 CPU
  Database: 1GB RAM, 1 CPU, 10GB storage
  Monitoring: 2GB RAM, 2 CPU total
  Infrastructure: 512MB RAM, 0.5 CPU

Production Planning:
  - Autoscaling configuration
  - Resource quotas
  - Priority classes
  - Node taints/tolerations
```

---

## 🔮 Future Architecture

### **Multi-Cluster Setup**
```
Production:
  - Multiple AZs
  - Cluster federation
  - Service mesh
  - Global load balancing
```

### **Advanced Features**
```
- GitOps with ArgoCD
- Service mesh with Istio
- Advanced security policies
- Automated scaling
- Disaster recovery
```

---

## 📋 Architecture Decisions

### **Why k3d for Development?**
- Docker-native, no system impact
- Easy cluster lifecycle management
- Perfect for local development
- Low resource overhead

### **Why Traefik?**
- Native Docker/Kubernetes integration
- Automatic SSL certificate management
- Cloudflare integration
- Built-in metrics and health checks

### **Why Prometheus/Grafana?**
- Proven monitoring stack
- Rich ecosystem of exporters
- Powerful visualization
- Active community support

---

## 🎯 Success Metrics

### **Performance Targets**
- Application response time: <200ms
- Database query time: <100ms
- Cluster resource utilization: <70%
- Monitoring alert response: <5min

### **Availability Goals**
- Development uptime: 90%+
- Staging uptime: 99%+
- Production uptime: 99.9%+

### **Development Velocity**
- Local setup time: <10min
- Deployment time: <5min
- Rollback time: <2min
- Test execution: <3min

---

*Architecture document v1.0 - Last Updated: $(date)*
