# 🔄 Migration Strategy

> Step-by-step migration plan from Docker Compose to Kubernetes for wetfish web-services.

---

## 📋 Migration Overview

### **Current State: Docker Compose**
```
Docker Host
├── Traefik (reverse proxy)
├── Wiki (Custom PHP + MariaDB)
├── Forum (Node.js + PostgreSQL)
├── Home (static site)
├── Danger (JavaScript sandbox)
└── Click (tracking service)
```

### **Target State: Kubernetes**
```
k3d Cluster
├── wetfish-system (Traefik + infrastructure)
├── wetfish-monitoring (observability stack)
├── wetfish-dev (applications)
└── wetfish-staging (testing)
```

---

## 🎯 Migration Phases

### **Phase 0: Preparation** ✅
**Goal**: Set up development environment and tools

#### **Tasks**
- [x] Install k3d and configure development cluster
- [x] Set up local container registry (k3d registry on :5000)
- [x] Create Kubernetes manifests structure
- [x] Set up monitoring stack values (Prometheus + Grafana Helm values)
- [x] Document all current service configurations

#### **Deliverables**
- Functional k3d cluster (1 server, 2 agents)
- Monitoring Helm values in `monitoring/values/`
- Service manifest structure (`services/<name>/k8s/`)
- Setup and deployment scripts

---

### **Phase 1: Pilot Service - Wiki** ✅
**Goal**: Successfully migrate one service end-to-end

#### **Tasks**
- [x] Analyze current Docker Compose wiki configuration
- [x] Containerize wiki (custom PHP app, NOT MediaWiki)
- [x] Create Kubernetes manifests (sidecar pattern: nginx + php-fpm)
- [x] Set up MariaDB 10.10 with persistent storage
- [x] Configure ServiceMonitor for metrics
- [x] Validate service functionality via Traefik ingress

#### **Deliverables**
- Wiki service running at `wiki.wetfish.local:8080`
- GitHub Actions CI/CD workflows for wiki images
- Sidecar pattern established as template for PHP services

---

### **Phase 2: Remaining Services** ✅
**Goal**: Migrate home, glitch, click, and danger

#### **Tasks**
- [x] Home: SvelteKit static site (single nginx container)
- [x] Glitch: PHP 5.6 + nginx sidecar (no database)
- [x] Click: PHP 5.6 + nginx sidecar + MariaDB 10.10
- [x] Danger: PHP 5.6 + nginx sidecar + MariaDB 10.10
- [x] Update setup-hosts.sh with new service DNS entries
- [x] Update all documentation

#### **Deliverables**
- 5 services running in k3d cluster
- All services accessible via Traefik ingress
- PHP 5.6 services using `php:5.6-fpm-alpine` base image

#### **Key Decisions**
- Used `php:5.6-fpm-alpine` instead of broken Sury PHP 5.6 repos
- MariaDB configs require explicit `collation-server` matching `character-set-server`
- Forum (SMF 2.1.6) deferred due to complexity

---

### **Phase 3: Forum Service** (deferred)
**Goal**: Migrate SMF 2.1.6 forum

#### **Tasks**
- [ ] Analyze SMF 2.1.6 build chain (PHP 8.4, composer, custom mods)
- [ ] Create Dockerfiles for forum
- [ ] Create Kubernetes manifests
- [ ] Set up MariaDB with forum schema
- [ ] Validate forum functionality

---

### **Phase 4: Production Ready**
**Goal**: Security hardening, backups, production cluster

#### **Tasks**
- [ ] Address security audit findings (see `docs/security-audit-action-items.md`)
- [ ] Implement TLS/HTTPS enforcement
- [ ] Replace hardcoded secrets with sealed secrets or external secret store
- [ ] Add network policies
- [ ] Add security contexts to all deployments
- [ ] Implement backup and restore procedures
- [ ] Set up staging environment

---

### **Phase 5: CI/CD and GitOps**
**Goal**: Full automation and multi-environment support

#### **Tasks**
- [ ] Add GitHub Actions workflows for all services
- [ ] Configure automated testing
- [ ] Implement rolling deployments
- [ ] Set up GitOps with ArgoCD
- [ ] Configure promotion to production

#### **Deliverables**
- Fully automated deployment pipeline
- Multi-environment support
- Production-ready configuration

---

## 🔧 Service Migration Details

### **Wiki Service Migration**

#### **Current Architecture**
```yaml
Docker Compose:
  wiki-web:
    image: wiki:latest
    ports: ["8080:80"]
    volumes: ["./data:/var/www/html"]
  
  wiki-db:
    image: mariadb:10.10
    environment:
      MYSQL_DATABASE: wiki
      MYSQL_USER: wiki
      MYSQL_PASSWORD: ${WIKI_DB_PASSWORD}
    volumes: ["./db:/var/lib/mysql"]
```

#### **Target Architecture**
```yaml
Kubernetes:
  - Namespace: wetfish-dev
  - Deployment: wiki-web (nginx + PHP-FPM sidecar)
  - Service: wiki-web (ClusterIP)
  - Ingress: wiki-ingress (Traefik)
  - ConfigMap: wiki-nginx-config, wiki-php-config
  - Secret: wiki-mysql-secret
  - PVC: wiki-wwwroot (2Gi), wiki-uploads (5Gi)
  - Deployment: wiki-mysql (MariaDB 10.10)
  - Service: wiki-mysql
  - PVC: wiki-mysql-data (2Gi)
```

#### **Migration Steps**
1. **Data Analysis**
   ```bash
   # Export current data
   docker exec wiki-db mysqldump -u root -p wiki > wiki-backup.sql
   
   # Analyze file structure
   docker exec wiki-web find /var/www/html -type f | head -20
   ```

2. **Container Creation**
   ```bash
   # Build custom wiki image
   docker build -t wetfish/wiki:k8s-v1 services/wiki/
   
   # Tag for local registry
   docker tag wetfish/wiki:k8s-v1 localhost:5000/wetfish/wiki:k8s-v1
   docker push localhost:5000/wetfish/wiki:k8s-v1
   ```

3. **Kubernetes Deployment**
   ```bash
   # Deploy database first
   kubectl apply -f services/wiki/kubernetes/01-database.yaml
   
   # Wait for database
   kubectl wait --for=condition=ready pod -l app=wiki-db -n wetfish-dev
   
   # Migrate data
   kubectl cp wiki-backup.sql wiki-db-pod:/tmp/wiki-backup.sql
   kubectl exec wiki-db-pod -- mysql -u root -p wiki < /tmp/wiki-backup.sql
   
   # Deploy application
   kubectl apply -f services/wiki/kubernetes/02-application.yaml
   
   # Configure ingress
   kubectl apply -f services/wiki/kubernetes/03-ingress.yaml
   ```

---

### **Forum Service Migration**

#### **Current Architecture**
```yaml
Docker Compose:
  forum:
    build: ./forum
    ports: ["3000:3000"]
    environment:
      DATABASE_URL: postgresql://user:pass@forum-db:5432/forum
  
  forum-db:
    image: postgres:15
    environment:
      POSTGRES_DB: forum
      POSTGRES_USER: forum
      POSTGRES_PASSWORD: ${FORUM_DB_PASSWORD}
    volumes: ["./forum-db:/var/lib/postgresql/data"]
```

#### **Migration Considerations**
- PostgreSQL to PostgreSQL migration (simpler)
- Node.js application containerization
- Database connection string management
- Session storage and caching

---

### **Static Sites (Home) Migration**

#### **Migration Strategy**
```yaml
Options:
  1. Static pod with hostPath volume
  2. Nginx container with ConfigMap
  3. External CDN integration

Recommended: Nginx container with ConfigMap
Benefits:
  - Containerized and versioned
  - Easy updates via ConfigMap
  - Can be served by Traefik
  - Consistent with other services
```

---

## 🔄 Data Migration Strategy

### **Database Migration Process**

#### **General Approach**
1. **Export** data from running containers
2. **Backup** entire data directory
3. **Import** into Kubernetes pods
4. **Validate** data integrity
5. **Switch** traffic to new deployment

#### **Migration Scripts**
```bash
#!/bin/bash
# migrate-wiki-db.sh

set -euo pipefail

NAMESPACE="wetfish-dev"
DB_POD="wiki-db-0"
BACKUP_FILE="wiki-backup-$(date +%Y%m%d).sql"

echo "Starting wiki database migration..."

# 1. Export data from Docker Compose
echo "Exporting data from Docker Compose..."
docker-compose exec -T wiki-db mysqldump -u root -p"$WIKI_ROOT_PASSWORD" wiki > "$BACKUP_FILE"

# 2. Copy to Kubernetes pod
echo "Copying backup to Kubernetes pod..."
kubectl cp "$BACKUP_FILE" "$NAMESPACE/$DB_POD:/tmp/wiki-backup.sql"

# 3. Import into Kubernetes database
echo "Importing data into Kubernetes database..."
kubectl exec "$NAMESPACE/$DB_POD" -- mysql -u root -p"$WIKI_ROOT_PASSWORD" wiki < /tmp/wiki-backup.sql

# 4. Validate
echo "Validating data migration..."
RECORDS=$(kubectl exec "$NAMESPACE/$DB_POD" -- mysql -u root -p"$WIKI_ROOT_PASSWORD" -e "SELECT COUNT(*) FROM page;" wiki | tail -1)
echo "Migrated $RECORDS pages"

echo "Wiki database migration completed!"
```

### **File Storage Migration**

#### **Wiki File Migration**
```bash
#!/bin/bash
# migrate-wiki-files.sh

NAMESPACE="wetfish-dev"
WIKI_POD=$(kubectl get pods -n $NAMESPACE -l app=wiki -o jsonpath='{.items[0].metadata.name}')

# 1. Sync files from Docker Compose volume
rsync -av --progress ./wiki-data/ /tmp/wiki-files/

# 2. Copy to Kubernetes pod
kubectl cp /tmp/wiki-files/ "$NAMESPACE/$WIKI_POD:/var/www/html/"

# 3. Set proper permissions
kubectl exec "$NAMESPACE/$WIKI_POD" -- chown -R www-data:www-data /var/www/html/

echo "Wiki files migration completed!"
```

---

## 🧪 Testing Strategy

### **Migration Testing Phases**

#### **Phase 1: Unit Testing**
```yaml
Tests:
  - Container builds successfully
  - Kubernetes manifests are valid
  - Database connections work
  - Configuration loading works
```

#### **Phase 2: Integration Testing**
```yaml
Tests:
  - Service startup and health checks
  - Database migrations
  - Inter-service communication
  - Ingress routing
```

#### **Phase 3: End-to-End Testing**
```yaml
Tests:
  - Full user workflows
  - File upload/download
  - User authentication
  - Performance benchmarks
```

#### **Phase 4: Load Testing**
```yaml
Tests:
  - Concurrent user scenarios
  - Database query performance
  - Resource usage monitoring
  - Memory leak detection
```

### **Test Automation**
```bash
#!/bin/bash
# test-migration.sh

set -euo pipefail

NAMESPACE="wetfish-dev"

echo "Running migration tests..."

# 1. Check pod status
kubectl wait --for=condition=ready pod -l app=wiki -n $NAMESPACE --timeout=300s

# 2. Test database connectivity
kubectl exec deployment/wiki -n $NAMESPACE -- php -r "
\$pdo = new PDO('mysql:host=wiki-db-service;dbname=wiki', 'wiki', '\$WIKI_PASSWORD');
\$stmt = \$pdo->query('SELECT COUNT(*) FROM page');
echo 'Database connection successful: ' . \$stmt->fetchColumn() . ' pages found';
"

# 3. Test web interface
curl -f http://wiki.wetfish.local/wiki/Main_Page > /dev/null
echo "Web interface accessible"

# 4. Test file uploads
# TODO: Implement file upload test

echo "All tests passed!"
```

---

## 📋 Migration Checklist

### **Pre-Migration**
- [x] Current system documentation complete
- [ ] Backup strategy validated
- [x] Test environment ready
- [x] Migration scripts written and tested
- [x] Rollback plan documented

### **Migration Execution**
- [x] Database schemas available (`schema.sql` for wiki, click, danger)
- [x] Containers built and tested (all 5 services)
- [x] Kubernetes manifests applied
- [x] Services validated (HTTP 200 on all endpoints)

### **Post-Migration**
- [x] Health checks passing (liveness/readiness probes on all pods)
- [x] Monitoring ServiceMonitor configured (wiki)
- [ ] Alert rules active
- [x] Documentation updated
- [ ] Old Docker Compose system decommissioned

---

## 🚨 Rollback Strategy

### **Rollback Triggers**
- Service health checks failing
- Database corruption detected
- Performance degradation >50%
- Security issues identified

### **Rollback Procedure**
```bash
#!/bin/bash
# rollback.sh

set -euo pipefail

echo "Starting rollback procedure..."

# 1. Stop Kubernetes services
kubectl scale deployment wiki-web --replicas=0 -n wetfish-dev

# 2. Start Docker Compose services
cd /path/to/docker-compose
docker-compose up -d

# 3. Verify services are running
docker-compose ps

echo "Rollback completed!"
```

### **Rollback Validation**
- [x] Docker Compose configs still available in original `web-services` repo
- [ ] Data integrity verified
- [ ] User access restored
- [ ] Monitoring alerts resolved

---

## 📊 Migration Timeline

```mermaid
gantt
    title Migration Timeline
    dateFormat  YYYY-MM-DD
    section Phase 0
    Preparation          :done, 2024-02-12, 7d
    section Phase 1
    Wiki Migration       :done, 2024-02-19, 14d
    section Phase 2
    Remaining Services   :done, 2024-03-04, 14d
    section Phase 3
    Forum Service        :2024-03-18, 14d
    section Phase 4
    Production Ready     :2024-04-01, 14d
    section Phase 5
    CI/CD & GitOps       :2024-04-15, 14d
```

---

## 🎯 Success Criteria

### **Phase 0 Complete** ✅
- [x] k3d cluster running with Traefik ingress
- [x] Local registry on port 5000
- [x] Monitoring Helm values created
- [x] Setup, deploy, cleanup, hosts, and test scripts

### **Phase 1 Complete** ✅
- [x] Wiki service fully functional in K8s (sidecar pattern)
- [x] MariaDB with persistent storage
- [x] GitHub Actions CI/CD workflows
- [x] ServiceMonitor for Prometheus

### **Phase 2 Complete** ✅
- [x] Home, glitch, click, danger services migrated
- [x] All services accessible via Traefik ingress
- [x] Documentation updated

### **Phase 3: Forum** (not started)
- [ ] SMF 2.1.6 forum service migrated
- [ ] Forum database with schema loaded

### **Phase 4: Production Ready** (not started)
- [ ] Security audit findings addressed
- [ ] TLS/HTTPS enforced
- [ ] Secrets management implemented
- [ ] Backup procedures validated

### **Phase 5: CI/CD & GitOps** (not started)
- [ ] Full CI/CD pipeline for all services
- [ ] Automated deployments working
- [ ] Multi-environment support
- [ ] GitOps with ArgoCD

---

## 🔧 Tools and Scripts

### **Migration Utilities**
- `migrate-wiki-db.sh` - Database migration
- `migrate-wiki-files.sh` - File storage migration
- `test-migration.sh` - Automated testing
- `rollback.sh` - Emergency rollback
- `cleanup.sh` - Post-migration cleanup

### **Monitoring Tools**
- Prometheus metrics collection
- Grafana dashboards
- Loki log aggregation
- Tempo distributed tracing

---

*Migration Strategy v1.0 - Last Updated: $(date)*
