# 🔧 k3s Setup Guide

> Complete guide for setting up k3s/k3d cluster for wetfish web-services Kubernetes migration.

---

## 📋 Prerequisites

### **System Requirements**
- **OS**: macOS (Apple Silicon tested)
- **Docker**: v20.10+ running and accessible
- **kubectl**: v1.24+ installed
- **Memory**: 8GB+ RAM recommended
- **Storage**: 20GB+ free space

### **Required Tools**
```bash
# Install Homebrew (if not already installed)
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

# Install kubectl (if not installed)
brew install kubectl

# Install k3d (Kubernetes in Docker)
brew install k3d

# Install Helm (for monitoring stack)
brew install helm
```

---

## 🚀 Quick Start Setup

### **1. Install k3d**
```bash
# Install k3d via Homebrew
brew install k3d

# Verify installation
k3d version
```

### **2. Create Development Cluster**
```bash
# Navigate to project directory
cd /path/to/web-services-k8s

# Full stack bring-up (cluster + infra + builds + deploy)
./scripts/up.sh

# Or with monitoring stack included
./scripts/up.sh --with-monitoring

# Or just create the cluster (no builds/deploys)
./scripts/setup-dev.sh
```

### **3. Verify Cluster Access**
```bash
# Check cluster status
kubectl cluster-info

# List nodes
kubectl get nodes

# List namespaces
kubectl get namespaces
```

---

## 🏗️ Cluster Configuration

### **Development Cluster Specs**
```bash
k3d cluster create wetfish-dev \
  --agents 2 \
  --servers 1 \
  --port 8080:80@loadbalancer \
  --port 8443:443@loadbalancer \
  --volume /Users/cyba/git/web-services-k8s:/src@all \
  --registry-create wetfish-registry:5000 \
  --api-port 6443 \
  --kubeconfig-switch-context \
  --timeout 120s
```

### **Cluster Features**
- **Nodes**: 1 server + 2 agents
- **Registry**: Local container registry on port 5000
- **Ingress**: HTTP(8080) + HTTPS(8443) exposed
- **Volumes**: Project directory mounted in all nodes
- **Context**: Automatic kubeconfig switching

### **Namespace Architecture**
```yaml
wetfish-system:      # Core infrastructure (Traefik)
cert-manager:        # TLS certificate management
wetfish-monitoring:  # Observability stack (Prometheus, Grafana, Loki, Tempo, Promtail)
wetfish-dev:         # Development applications
wetfish-staging:     # Staging applications
wetfish-prod:        # Production applications
```

---

## 📁 Directory Structure

```
web-services-k8s/
├── scripts/
│   ├── up.sh                # Full stack bring-up (one command)
│   ├── setup-dev.sh         # Cluster creation only
│   ├── deploy.sh            # Service deployment (--env dev|staging|prod)
│   ├── generate-secrets.sh  # Secret generation per environment
│   ├── cleanup.sh           # Cluster teardown
│   ├── setup-hosts.sh       # /etc/hosts management
│   └── test-deployment.sh   # Health checks
├── infrastructure/
│   ├── namespaces.yaml      # Namespace definitions (dev, staging, prod, system, monitoring)
│   ├── traefik/             # Traefik raw manifests
│   └── cert-manager/        # ClusterIssuer definitions
├── monitoring/
│   └── values/              # Helm values for monitoring stack
│       ├── prometheus-stack-values.yaml
│       ├── loki-values.yaml
│       ├── tempo-values.yaml
│       └── promtail-values.yaml
├── services/
│   ├── wiki/                # Wiki service
│   ├── home/                # Home service
│   ├── glitch/              # Glitch service
│   ├── click/               # Click service
│   └── danger/              # Danger service
│   # Each service has:
│   #   src/          - Git submodule (upstream source)
│   #   k8s/base/     - Kustomize base manifests
│   #   k8s/overlays/ - dev/staging/prod overlays
│   #   Dockerfile.*  - Container definitions
│   #   config/       - nginx.conf, php.ini, etc.
├── .github/workflows/       # CI/CD workflows
│   ├── build-service.yml    # Reusable workflow
│   ├── build-wiki.yml       # Per-service triggers
│   └── ...
└── docs/                    # Documentation
```

---

## 🛠️ Cluster Management Commands

### **Lifecycle Management**
```bash
# Start cluster
k3d cluster start wetfish-dev

# Stop cluster (preserves data)
k3d cluster stop wetfish-dev

# Delete cluster (removes data)
k3d cluster delete wetfish-dev

# List clusters
k3d cluster list
```

### **Development Workflow**
```bash
# Switch to cluster context
kubectl config use-context k3d-wetfish-dev

# Access cluster info
kubectl cluster-info

# View all resources
kubectl get all --all-namespaces

# Port forwarding
kubectl port-forward svc/service-name 8080:80 -n wetfish-dev
```

### **Registry Operations**
```bash
# List local images
docker images | grep wetfish

# Tag for local registry
docker tag my-image localhost:5000/my-image

# Push to local registry
docker push localhost:5000/my-image

# Pull in cluster
kubectl run test --image localhost:5000/my-image
```

---

## 🔍 Troubleshooting

### **Common Issues**

#### **Cluster Access Problems**
```bash
# Reset kubectl context
kubectl config use-context k3d-wetfish-dev

# Check cluster status
k3d cluster list

# Recreate cluster (if needed)
k3d cluster delete wetfish-dev
./scripts/setup-dev.sh
```

#### **Docker Desktop Issues**
```bash
# Restart Docker Desktop
# Check Docker is running
docker info
docker ps

# Restart k3d cluster
k3d cluster restart wetfish-dev
```

#### **Registry Access**
```bash
# Test registry connectivity
curl http://localhost:5000/v2/_catalog

# Check registry logs
docker logs k3d-wetfish-dev-registry
```

#### **Port Conflicts**
```bash
# Check what's using ports
lsof -i :8080
lsof -i :8443
lsof -i :5000

# Kill conflicting processes
kill -9 <PID>

# Recreate cluster with different ports
k3d cluster create wetfish-dev --port 8081:80@loadbalancer
```

#### **Memory Issues**
```bash
# Check cluster resource usage
kubectl top nodes
kubectl top pods --all-namespaces

# Increase Docker Desktop memory allocation
# Docker Desktop > Settings > Resources > Memory > 8GB+
```

### **Debug Commands**
```bash
# Check pod logs
kubectl logs -f deployment/name -n wetfish-dev

# Describe resources
kubectl describe pod pod-name -n wetfish-dev
kubectl describe service service-name -n wetfish-dev

# Execute in pod
kubectl exec -it deployment/name -n wetfish-dev -- bash

# Check events
kubectl get events -n wetfish-dev --sort-by=.metadata.creationTimestamp
```

---

## 🔐 Security Considerations

### **Development Environment**
- **Network**: Cluster isolated to local machine
- **Registry**: Local Docker registry (no external access)
- **Secrets**: Local development only
- **Access**: Single-user kubectl access

### **Security Best Practices**
```bash
# Use non-root containers
# Implement resource limits
# Configure network policies
# Use RBAC for production
# Encrypt secrets at rest
```

---

## 📊 Performance Tuning

### **Resource Allocation**
```yaml
# Recommended settings for M1 Pro
cluster:
  memory: 4GB minimum
  cpu: 4 cores minimum
  
node:
  agent:
    memory: 1GB each
    cpu: 1 core each
  server:
    memory: 2GB
    cpu: 2 cores
```

### **Optimization Tips**
- Use local volume mounts for development
- Enable image caching in k3d
- Limit cluster resources to prevent system overload
- Use ARM64-native images on Apple Silicon

---

## 📚 References

- [k3d Documentation](https://k3d.io/)
- [Kubernetes Documentation](https://kubernetes.io/docs/)
- [Traefik Ingress Guide](https://doc.traefik.io/traefik/)
- [Helm Charts](https://helm.sh/docs/)

---

## 🤝 Support

For wetfish-specific issues:
1. Check [troubleshooting.md](./troubleshooting.md)
2. Review [architecture design](./architecture-design.md)
3. Create GitHub issue with detailed logs

---

*Last Updated: $(date)*