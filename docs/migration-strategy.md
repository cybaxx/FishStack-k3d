# 🔄 Migration Strategy

> Step-by-step migration plan from Docker Compose to Kubernetes for wetfish web-services.

---

## 📋 Migration Overview

### **Current State: Docker Compose**
```
Docker Host
├── Traefik (reverse proxy)
├── Wiki (MediaWiki + MariaDB)
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

### **Phase 0: Preparation (Week 1)**
**Goal**: Set up development environment and tools

#### **Tasks**
- [ ] Install k3d and configure development cluster
- [ ] Set up local container registry
- [ ] Create Kubernetes manifests structure
- [ ] Set up monitoring stack (Prometheus + Grafana)
- [ ] Document all current service configurations

#### **Deliverables**
- Functional k3d cluster
- Basic monitoring dashboards
- Empty service manifests
- Setup documentation

---

### **Phase 1: Pilot Service - Wiki (Week 2-3)**
**Goal**: Successfully migrate one service end-to-end

#### **Tasks**
- [ ] Analyze current Docker Compose wiki configuration
- [ ] Containerize Wiki with custom extensions
- [ ] Create Kubernetes manifests for wiki deployment
- [ ] Set up MariaDB with persistent storage
- [ ] Configure monitoring and alerting
- [ ] Test data migration procedures
- [ ] Validate service functionality

#### **Deliverables**
- Wiki service running in Kubernetes
- Database migration scripts
- Monitoring dashboards
- Deployment automation

---

### **Phase 2: Core Services (Week 4-5)**
**Goal**: Migrate essential services (forum, home)

#### **Tasks**
- [ ] Containerize forum application (Node.js + PostgreSQL)
- [ ] Migrate home page to Kubernetes (static site)
- [ ] Set up inter-service communication
- [ ] Configure service discovery
- [ ] Implement backup and restore procedures
- [ ] Set up comprehensive monitoring

#### **Deliverables**
- Forum and home services running
- Service mesh communication
- Automated backups
- Complete monitoring coverage

---

### **Phase 3: Advanced Services (Week 6-7)**
**Goal**: Migrate remaining services (danger, click)

#### **Tasks**
- [ ] Migrate JavaScript sandbox (danger)
- [ ] Migrate tracking service (click)
- [ ] Set up advanced security policies
- [ ] Configure advanced networking
- [ ] Implement performance optimizations

#### **Deliverables**
- All services migrated
- Security hardening
- Performance tuning
- Network policies

---

### **Phase 4: CI/CD and Automation (Week 8)**
**Goal**: Implement full GitOps workflow

#### **Tasks**
- [ ] Set up GitHub Actions pipelines
- [ ] Configure automated testing
- [ ] Implement rolling deployments
- [ ] Set up staging environment
- [ ] Configure promotion to production

#### **Deliverables**
- Fully automated deployment pipeline
- Staging environment
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
  - Deployment: wiki-app (MediaWiki + PHP-FPM)
  - Service: wiki-service (ClusterIP)
  - Ingress: wiki-ingress (Traefik)
  - ConfigMap: wiki-config
  - Secret: wiki-secrets
  - PVC: wiki-storage (5GB)
  - Deployment: wiki-db (MariaDB)
  - Service: wiki-db-service
  - PVC: wiki-db-storage (10GB)
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

#### **MediaWiki File Migration**
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
- [ ] Current system documentation complete
- [ ] Backup strategy validated
- [ ] Test environment ready
- [ ] Migration scripts written and tested
- [ ] Rollback plan documented

### **Migration Execution**
- [ ] Database exported successfully
- [ ] File storage backed up
- [ ] Containers built and tested
- [ ] Kubernetes manifests applied
- [ ] Data imported successfully
- [ ] Services validated

### **Post-Migration**
- [ ] Health checks passing
- [ ] Monitoring configured
- [ ] Alert rules active
- [ ] Documentation updated
- [ ] Old system decommissioned

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
kubectl scale deployment wiki --replicas=0 -n wetfish-dev

# 2. Start Docker Compose services
cd /path/to/docker-compose
docker-compose up -d

# 3. Verify services are running
docker-compose ps

echo "Rollback completed!"
```

### **Rollback Validation**
- [ ] Docker Compose services healthy
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
    Preparation      :2024-02-12, 7d
    section Phase 1
    Wiki Migration   :2024-02-19, 14d
    section Phase 2
    Core Services   :2024-03-04, 14d
    section Phase 3
    Advanced Services:2024-03-18, 14d
    section Phase 4
    CI/CD Pipeline  :2024-04-01, 7d
```

---

## 🎯 Success Criteria

### **Phase 0 Complete**
- [ ] k3d cluster running with monitoring
- [ ] All current configurations documented
- [ ] Migration scripts tested and validated

### **Phase 1 Complete**
- [ ] Wiki service fully functional in K8s
- [ ] Data migrated and verified
- [ ] Monitoring and alerting active
- [ ] Deployment process automated

### **Phase 2 Complete**
- [ ] Forum and home services migrated
- [ ] Inter-service communication working
- [ ] Backup procedures validated
- [ ] Performance benchmarks met

### **Phase 3 Complete**
- [ ] All services migrated
- [ ] Security policies implemented
- [ ] Performance optimized
- [ ] Documentation complete

### **Phase 4 Complete**
- [ ] Full CI/CD pipeline operational
- [ ] Automated deployments working
- [ ] Production-ready configuration
- [ ] Team training completed

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
