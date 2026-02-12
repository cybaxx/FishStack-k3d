# 🌊 Wetfish Web-Services K8s

> Kubernetes migration of wetfish web-services with complete observability stack based on FishVision monitoring model.

---

## 🎯 Project Overview

This project migrates the wetfish web-services from Docker Compose to Kubernetes with:
- **Infrastructure**: On-prem k3d cluster for development
- **Ingress**: Traefik v2 with Cloudflare integration
- **Pilot Service**: Wiki (custom PHP application with nginx + php-fpm + MariaDB)
- **Monitoring**: Full observability stack (Prometheus, Grafana, Loki, Tempo)
- **CI/CD**: GitHub Actions with GHCR container registry

---

## 🏗️ Architecture

### **Current Development Stack**
```
┌─────────────────────────────────────────────────────────┐
│                   k3d Cluster                      │
├─────────────────────────────────────────────────────────┤
│  wetfish-system    │  wetfish-dev  │ wetfish-monitoring │
│  (Traefik)        │  (Wiki App)   │  (Observability)   │
└─────────────────────────────────────────────────────────┘
```

### **Monitoring Stack (FishVision Model)**
```
Applications → Metrics → Prometheus → Alertmanager → IRC/Webhook
                ↓           ↓           ↓
              Logs → Loki → Grafana ←───────┘
                ↓           ↓
             Traces → Tempo → Distributed Tracing
```

---

## 🚀 Quick Start (Development)

### **Prerequisites**
- Docker Desktop or Docker Engine
- k3d (Kubernetes)
- kubectl
- helm (Kubernetes package manager)
- GitHub CLI (for authentication)

### **1. Setup Development Environment**
```bash
# Clone repository
git clone git@github.com:cybaxx/web-services-k8s.git
cd web-services-k8s
git checkout dev-init-1

# Setup k3d cluster and dependencies
./scripts/setup-dev.sh

# Setup DNS entries for local access
sudo ./scripts/setup-hosts.sh
```

### **2. Deploy Wiki Service**
```bash
# Deploy wiki application
./scripts/deploy.sh wetfish-dev wiki

# Wait for rollout
kubectl rollout status deployment/wiki-web -n wetfish-dev

# Run health checks
./scripts/test-deployment.sh wetfish-dev wiki
```

### **3. Access Services**
```bash
# Wiki Application
open http://wiki.wetfish.local

# Monitoring Stack
open http://grafana.wetfish.local  # admin/admin
open http://prometheus.wetfish.local
open http://loki.wetfish.local
open http://tempo.wetfish.local
```

---

## 📊 Monitoring & Observability

Based on the proven FishVision monitoring stack:

### **Metrics Collection**
- **Prometheus**: Scrapes application and cluster metrics
- **Node Exporter**: Host-level metrics
- **Service Monitors**: Kubernetes service discovery

### **Alerting**
- **Alertmanager**: Routes and manages alerts
- **IRC Relay**: Real-time notifications via webhook
- **Alert Rules**: CPU, memory, disk, application health

### **Visualization**
- **Grafana**: Dashboards for metrics, logs, and traces
- **Loki**: Log aggregation and querying
- **Tempo**: Distributed tracing

### **Key Dashboards**
- Kubernetes cluster overview
- Wiki application metrics
- Infrastructure health
- Custom alert status

---

## 🛠️ Development Workflow

### **Git Workflow**
```
feature/branch → PR → dev-init-1 → (testing) → main → staging → production
```

### **CI/CD Pipeline**
1. **Push to dev-init-1** → GitHub Actions CI
2. **Build & Test** → Container images to GHCR
3. **Deploy to Dev** → Automatic k3d deployment
4. **Health Checks** → Monitoring verification

### **Container Registry**
- **Registry**: GitHub Container Registry (GHCR)
- **Naming**: `ghcr.io/cybaxx/web-services-k8s/wiki:dev-init-1`
- **Tags**: Branch-based + SHA for reproducibility

---

## 📁 Project Structure

```
web-services-k8s/
├── .github/workflows/     # CI/CD pipelines
├── services/            # Application containers
│   └── wiki/           # Wiki service (pilot)
├── monitoring/          # Observability stack
│   ├── manifests/       # K8s deployments
│   ├── configs/         # Prometheus, Grafana, etc.
│   └── grafana/        # Dashboard definitions
├── infrastructure/      # Core infrastructure
│   └── traefik/       # Ingress controller
├── scripts/            # Automation scripts
└── docs/              # Documentation
```

---

## 🔧 Local Development Commands

### **Cluster Management**
```bash
# Start/stop k3d cluster
k3d cluster start wetfish-dev
k3d cluster stop wetfish-dev

# Access cluster info
kubectl cluster-info
kubectl get nodes
kubectl get namespaces
```

### **Application Management**
```bash
# Deploy services
./scripts/deploy.sh wetfish-dev wiki

# Run health checks
./scripts/test-deployment.sh wetfish-dev wiki

# Check deployment status
kubectl get pods -n wetfish-dev
kubectl get services -n wetfish-dev
kubectl get ingress -n wetfish-dev

# View logs (nginx container)
kubectl logs deployment/wiki-web -n wetfish-dev -c nginx -f

# View logs (php-fpm container)
kubectl logs deployment/wiki-web -n wetfish-dev -c php-fpm -f

# Access container shell (nginx)
kubectl exec -it deployment/wiki-web -n wetfish-dev -c nginx -- sh

# Access container shell (php-fpm)
kubectl exec -it deployment/wiki-web -n wetfish-dev -c php-fpm -- bash
```

### **Monitoring Access**
```bash
# Port forwarding for local access
kubectl port-forward svc/grafana 3000:3000 -n wetfish-monitoring
kubectl port-forward svc/prometheus 9090:9090 -n wetfish-monitoring

# View monitoring targets
kubectl get servicemonitors -n wetfish-monitoring
```

---

## 📋 Current Status (dev-init-1)

### **✅ Completed**
- [x] Repository structure
- [x] Git workflow (feature branch approach)
- [x] Monitoring stack design (FishVision-based)
- [x] CI/CD pipeline plan

### **🚧 In Progress**
- [ ] Wiki service containerization
- [ ] K3s cluster setup scripts
- [ ] Traefik ingress configuration
- [ ] GitHub Actions workflows

### **📋 Next Steps**
1. Containerize wiki service with Docker
2. Create Kubernetes manifests for wiki deployment
3. Deploy monitoring stack (Prometheus, Grafana, Loki, Tempo)
4. Set up GitHub Actions CI/CD pipeline
5. Test end-to-end deployment

---

## 🔐 Security Configuration

### **Development Environment**
- **Cluster**: Single-user k3d setup
- **Access**: kubectl with local kubeconfig
- **Registry**: GitHub Container Registry (personal)
- **Secrets**: Local development only

### **Security Best Practices**
- Non-root containers
- Resource limits and requests
- Network policies (when ready)
- RBAC configuration
- Secret management

---

## 🐛 Troubleshooting

### **Common Issues**

#### **Cluster Access**
```bash
# Reset kubectl context
kubectl config use-context k3d-wetfish-dev

# Check cluster status
k3d cluster list
kubectl get nodes
```

#### **Service Access**
```bash
# Check DNS resolution
nslookup wiki.wetfish.local

# Verify ingress
kubectl get ingress -n wetfish-dev
kubectl describe ingress wiki-ingress -n wetfish-dev
```

#### **Monitoring**
```bash
# Check Prometheus targets
curl http://localhost:9090/api/v1/targets

# View Grafana data sources
curl http://localhost:3000/api/datasources
```

---

## 🤝 Contributing

1. **Feature branches**: Create from `dev-init-1`
2. **Pull requests**: Target `dev-init-1` for initial development
3. **Testing**: Verify deployment to k3d before PR
4. **Documentation**: Update README and relevant docs

---

## 📞 Support

- **Repository**: https://github.com/cybaxx/web-services-k8s
- **Issues**: Create GitHub issue for bugs/features
- **Discussions**: Use GitHub Discussions for questions

---

## 📍 Roadmap

### **Phase 1: Foundation (Current)**
- [x] Repository setup
- [ ] Wiki service deployment
- [ ] Monitoring stack
- [ ] Basic CI/CD

### **Phase 2: Production Ready**
- [ ] Production cluster configuration
- [ ] Advanced monitoring
- [ ] Security hardening
- [ ] Backup strategies

### **Phase 3: Scale Out**
- [ ] Additional services (forum, home, danger, click)
- [ ] Multi-environment support
- [ ] Advanced CI/CD (helm charts)
- [ ] Team collaboration features

---

🚀 **Made with ❤️ for the wetfish community**