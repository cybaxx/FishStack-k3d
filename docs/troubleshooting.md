# 🔧 Troubleshooting Guide

> Common issues and solutions for wetfish web-services Kubernetes setup and monitoring.

---

## 🚨 Quick Reference

### **Emergency Commands**
```bash
# Stop all deployments immediately
kubectl scale deployment --all --replicas=0 --all-namespaces

# Restart cluster
k3d cluster restart wetfish-dev

# Check system health
kubectl get pods --all-namespaces | grep -v Running

# Access emergency shell
kubectl exec -it deployment/wiki-web -n wetfish-dev -c php-fpm -- bash
```

---

## 🏗️ Cluster Issues

### **Cluster Not Starting**

#### **Symptoms**
- `k3d cluster list` shows cluster stopped
- `kubectl get nodes` returns connection refused
- Docker Desktop errors

#### **Solutions**

**1. Check Docker Status**
```bash
# Verify Docker is running
docker info
docker ps

# Restart Docker Desktop
# (GUI: Docker Desktop → Restart)

# Clear Docker resources if needed
docker system prune -a
```

**2. Recreate Cluster**
```bash
# Delete existing cluster
k3d cluster delete wetfish-dev

# Clean up any remaining resources
kubectl config delete-context k3d-wetfish-dev

# Create new cluster
./scripts/setup-dev.sh
```

**3. Check Resource Availability**
```bash
# Check memory usage
free -h

# Check Docker Desktop resources
# Settings → Resources → Memory (8GB+ recommended)

# Check disk space
df -h
```

#### **Prevention**
- Allocate adequate memory to Docker Desktop
- Regular cleanup of unused images/volumes
- Monitor system resources during development

---

### **Pods Stuck in Pending**

#### **Symptoms**
```bash
kubectl get pods -n wetfish-dev
NAME                     READY   STATUS    RESTARTS   AGE
wiki-7d8f9c8b9-xyz12    0/1     Pending   0          5m
```

#### **Common Causes & Solutions**

**1. Insufficient Resources**
```bash
# Check resource requests/limits
kubectl describe pod wiki-7d8f9c8b9-xyz12 -n wetfish-dev

# Check node resources
kubectl describe nodes
kubectl top nodes

# Solution: Adjust resource requests
kubectl patch deployment wiki -n wetfish-dev -p '{"spec":{"template":{"spec":{"containers":[{"name":"wiki","resources":{"requests":{"memory":"256Mi","cpu":"100m"}}]}}}}'
```

**2. PVC Issues**
```bash
# Check PVC status
kubectl get pvc -n wetfish-dev

# Check storage classes
kubectl get storageclass

# Solution: Delete and recreate PVC
kubectl delete pvc wiki-wwwroot -n wetfish-dev
# Kubernetes will recreate based on PVC template
```

**3. Image Pull Issues**
```bash
# Check image availability
docker images | grep wetfish

# Check registry connectivity
curl http://localhost:5000/v2/_catalog

# Solution: Push image to local registry
docker tag wiki:latest localhost:5000/wiki:latest
docker push localhost:5000/wiki:latest
```

---

### **Service Not Accessible**

#### **Symptoms**
- Service exists but endpoints not found
- Connection refused errors
- Timeouts

#### **Troubleshooting Steps**

**1. Check Service Configuration**
```bash
# Get service details
kubectl get svc wiki-web -n wetfish-dev -o wide

# Check endpoints
kubectl get endpoints wiki-web -n wetfish-dev

# Describe service
kubectl describe svc wiki-web -n wetfish-dev
```

**2. Verify Pod Labels**
```bash
# Check pod labels
kubectl get pods -n wetfish-dev --show-labels

# Check service selector
kubectl get svc wiki-web -n wetfish-dev -o yaml | grep selector

# Ensure labels match selector
```

**3. Test Pod Connectivity**
```bash
# Test from within cluster
kubectl run test-pod --image=busybox --rm -it --restart=Never -- nslookup wiki-web.wetfish-dev.svc.cluster.local

# Test port accessibility
kubectl run test-pod --image=busybox --rm -it --restart=Never -- wget -qO- http://wiki-web.wetfish-dev.svc.cluster.local:80
```

---

## 🌐 Ingress Issues

### **Traefik Not Routing**

#### **Symptoms**
- 404 errors from Traefik
- 502 Bad Gateway
- SSL certificate errors

#### **Troubleshooting**

**1. Check Ingress Configuration**
```bash
# Get ingress status
kubectl get ingress -n wetfish-dev

# Describe ingress
kubectl describe ingress wiki-ingress -n wetfish-dev

# Check Traefik logs
kubectl logs -n wetfish-system deployment/traefik -f
```

**2. Verify DNS Resolution**
```bash
# Check local DNS
nslookup wiki.wetfish.local

# Add to /etc/hosts if needed
echo "127.0.0.1 wiki.wetfish.local" | sudo tee -a /etc/hosts

# Test HTTP access
curl -v http://wiki.wetfish.local
```

**3. Check Service Health**
```bash
# Verify service is running
kubectl get endpoints wiki-web -n wetfish-dev

# Check health endpoints
kubectl exec deployment/wiki-web -n wetfish-dev -- curl localhost:80/health

# Verify Traefik can reach service
kubectl exec deployment/traefik -n wetfish-system -- wget -qO- http://wiki-web.wetfish-dev.svc.cluster.local:80
```

---

## 📊 Monitoring Issues

### **Prometheus Not Scraping**

#### **Symptoms**
- No targets in Prometheus UI
- Grafana showing no data
- ServiceMonitors not working

#### **Solutions**

**1. Check ServiceMonitor Configuration**
```bash
# List ServiceMonitors
kubectl get servicemonitors -A

# Check specific ServiceMonitor
kubectl describe servicemonitor wiki-metrics -n wetfish-dev

# Verify service has metrics port
kubectl get svc wiki-web -n wetfish-dev -o yaml
```

**2. Check Prometheus Configuration**
```bash
# Check Prometheus logs
kubectl logs prometheus-prometheus-kube-prometheus-prometheus-0 -n wetfish-monitoring --tail=50

# Port-forward and check targets
kubectl port-forward svc/prometheus-kube-prometheus-prometheus 9090:9090 -n wetfish-monitoring
# Visit http://localhost:9090/targets
```

**3. Verify Metrics Endpoint**
```bash
# Test metrics endpoint from cluster
kubectl run test-metrics --image=curlimages/curl --rm -it --restart=Never -- curl http://wiki-web.wetfish-dev.svc.cluster.local:80/metrics

# Check if metrics are exposed
kubectl exec deployment/wiki-web -n wetfish-dev -- curl localhost:80/metrics
```

### **Grafana Dashboard Issues**

#### **Symptoms**
- Dashboards not loading
- No data displayed
- Datasource connection errors

#### **Solutions**

**1. Check Datasource Configuration**
```bash
# Port-forward Grafana
kubectl port-forward svc/prometheus-grafana 3000:80 -n wetfish-monitoring

# Check datasources (admin/admin)
curl -u admin:admin http://localhost:3000/api/datasources

# Test from Grafana pod
kubectl exec deployment/prometheus-grafana -n wetfish-monitoring -- \
  curl -s http://prometheus-kube-prometheus-prometheus:9090/api/v1/query?query=up
```

**2. Restart Grafana**
```bash
kubectl rollout restart deployment/prometheus-grafana -n wetfish-monitoring
```

---

## 🗄️ Database Issues

### **MariaDB Connection Failures**

#### **Symptoms**
- Database connection timeouts
- Authentication failures
- Slow query performance

#### **Troubleshooting**

**1. Check Database Pod**
```bash
# Check pod status
kubectl get pods -l app=wiki-mysql -n wetfish-dev

# Check database logs
kubectl logs deployment/wiki-mysql -n wetfish-dev

# Test database connection
kubectl exec deployment/wiki-mysql -n wetfish-dev -- mysql -u root -p$MYSQL_ROOT_PASSWORD -e "SHOW DATABASES;"
```

**2. Verify Network Connectivity**
```bash
# Test from application pod
kubectl exec deployment/wiki-web -n wetfish-dev -- telnet wiki-mysql-service.wetfish-dev.svc.cluster.local 3306

# Check service endpoints
kubectl get endpoints wiki-mysql-service -n wetfish-dev

# Test DNS resolution
kubectl run test-dns --image=busybox --rm -it --restart=Never -- nslookup wiki-mysql-service.wetfish-dev.svc.cluster.local
```

**3. Check Configuration**
```bash
# Review database secrets
kubectl get secret wiki-mysql-secret -n wetfish-dev -o yaml

# Check environment variables
kubectl exec deployment/wiki-web -n wetfish-dev -- env | grep MYSQL

# Verify configuration files
kubectl exec deployment/wiki-mysql -n wetfish-dev -- cat /etc/mysql/my.cnf
```

### **Data Migration Issues**

#### **Symptoms**
- Data not appearing in new database
- Character encoding problems
- Permission errors

#### **Solutions**

**1. Verify Data Integrity**
```bash
# Check export file
head -20 wiki-backup.sql | grep CREATE

# Check data count
grep "INSERT INTO" wiki-backup.sql | wc -l

# Verify character encoding
file -bi wiki-backup.sql
```

**2. Test Import Process**
```bash
# Test with small sample
head -100 wiki-backup.sql | kubectl exec wiki-mysql-pod -i -- mysql -u root -p database_name

# Check for errors
kubectl logs wiki-mysql-pod | grep ERROR

# Verify import
kubectl exec wiki-mysql-pod -- mysql -u root -p database_name -e "SELECT COUNT(*) FROM page;"
```

---

## 🔒 Security Context Issues

### **CreateContainerConfigError: runAsNonRoot**

#### **Symptoms**
```
Error: container has runAsNonRoot and image will run as root
Error: container has runAsNonRoot and image has non-numeric user (root)
```

#### **Root Cause**
Pod-level `securityContext.runAsNonRoot: true` or container-level `capabilities: drop: ["ALL"]` conflicts with images that run as root. Affected images:
- **nginx** (1.25-alpine) - runs as root
- **php-fpm** (php:5.6-fpm-alpine and Debian bookworm) - runs as root
- **MariaDB** (10.10) - needs root for `chown` on `/var/lib/mysql` during init

#### **Solutions**

**For web pods (nginx/php-fpm):** Remove `runAsNonRoot: true` from pod securityContext. Keep only `seccompProfile: RuntimeDefault`.

**For MariaDB:** Remove restrictive container securityContext (`capabilities: drop: ["ALL"]`). MariaDB needs CHOWN, DAC_OVERRIDE, FOWNER, SETUID, SETGID capabilities for data directory initialization.

**For Traefik:** Use the built-in non-root user: `runAsUser: 65532`, `runAsGroup: 65532`, and add `NET_BIND_SERVICE` capability.

### **MariaDB CrashLoopBackOff: chown Operation not permitted**

#### **Symptoms**
```
chown: changing ownership of '/var/lib/mysql/': Operation not permitted
```

#### **Root Cause**
Container securityContext with `capabilities: drop: ["ALL"]` prevents MariaDB from running `chown` during initialization. Even adding `SETUID`/`SETGID` is insufficient - MariaDB also needs `CHOWN`, `DAC_OVERRIDE`, and `FOWNER`.

#### **Solution**
Remove the restrictive container securityContext from MySQL deployments entirely. MariaDB requires root privileges for data directory initialization.

### **Wiki Nginx Restart Loop (Liveness Probe Failure)**

#### **Symptoms**
- nginx container restarts every ~30 seconds
- Exit code 0 (graceful shutdown from SIGTERM)
- `httpGet` liveness probe on `/` returns 500

#### **Root Cause**
The wiki app returns HTTP 500 when the database schema hasn't been loaded yet. The `httpGet` liveness probe interprets this as unhealthy and kills the container.

#### **Solution**
Use `tcpSocket` probes instead of `httpGet` for services where the application may return non-200 responses during initialization:
```yaml
livenessProbe:
  tcpSocket:
    port: 80
  initialDelaySeconds: 10
  periodSeconds: 10
```

---

## 🚀 Deployment Issues

### **Rolling Deployment Failures**

#### **Symptoms**
- Deployment stuck in progress
- Readiness probe failures
- Crash loops

#### **Solutions**

**1. Check Deployment Status**
```bash
# Get deployment status
kubectl rollout status deployment/wiki-web -n wetfish-dev

# Check rollout history
kubectl rollout history deployment/wiki-web -n wetfish-dev

# Describe deployment
kubectl describe deployment/wiki-web -n wetfish-dev
```

**2. Investigate Pod Issues**
```bash
# Check pod events
kubectl get events -n wetfish-dev --sort-by=.metadata.creationTimestamp

# Check pod logs
kubectl logs deployment/wiki-web -n wetfish-dev --previous

# Check resource usage
kubectl top pods -n wetfish-dev
```

**3. Manual Rollback**
```bash
# Rollback to previous revision
kubectl rollout undo deployment/wiki-web -n wetfish-dev

# Rollback to specific revision
kubectl rollout undo deployment/wiki-web -n wetfish-dev --to-revision=2

# Restart deployment
kubectl rollout restart deployment/wiki-web -n wetfish-dev
```

---

## 🔧 Development Environment Issues

### **Port Conflicts**

#### **Symptoms**
- Service already bound to port
- k3d cluster creation failures
- Ingress not accessible

#### **Solutions**

**1. Find Conflicting Processes**
```bash
# Check port usage
lsof -i :8080
lsof -i :8443
lsof -i :5000

# Kill conflicting processes
kill -9 <PID>

# Alternative: use different ports
k3d cluster create wetfish-dev --port 8081:80@loadbalancer
```

**2. Update Configuration**
```bash
# Update /etc/hosts with new port
echo "127.0.0.1 wiki.wetfish.local:8081" | sudo tee -a /etc/hosts

# Update URLs in documentation
sed -i 's/:8080/:8081/g' docs/*.md
```

---

## 🧪 Testing and Debugging

### **Debug Commands**

**Container Debugging**
```bash
# Access container shell
kubectl exec -it deployment/wiki-web -n wetfish-dev -c php-fpm -- bash

# Run commands in container
kubectl exec deployment/wiki-web -n wetfish-dev -- ps aux
kubectl exec deployment/wiki-web -n wetfish-dev -- netstat -tulpn

# Copy files to/from container
kubectl cp local-file wiki-web-pod:/remote-path/
kubectl cp wiki-web-pod:/remote-path/ remote-file
```

**Network Debugging**
```bash
# Test DNS resolution
kubectl run dns-test --image=busybox --rm -it --restart=Never -- nslookup google.com

# Test connectivity
kubectl run net-test --image=nicolaka/netshoot --rm -it --restart=Never -- bash

# Port forwarding
kubectl port-forward svc/wiki-web 8080:80 -n wetfish-dev
```

**Resource Debugging**
```bash
# Monitor resource usage
kubectl top pods -n wetfish-dev --containers
kubectl top nodes

# Check resource quotas
kubectl get resourcequota -n wetfish-dev

# Check limits
kubectl describe namespace wetfish-dev
```

---

## 📋 Maintenance Commands

### **Regular Maintenance**

**Cleanup Commands**
```bash
# Clean up unused resources
kubectl delete pods --field-selector=status.phase=Succeeded -A
kubectl delete pods --field-selector=status.phase=Failed -A

# Clean Docker resources
docker system prune -a
docker volume prune

# Clean k3d resources
k3d cluster list
k3d cluster delete <unused-cluster>
```

**Backup Commands**
```bash
# Backup configurations
kubectl get all -n wetfish-dev -o yaml > backup-wetfish-dev.yaml

# Backup database
kubectl exec deployment/wiki-mysql -n wetfish-dev -- mysqldump -u root -p$MYSQL_ROOT_PASSWORD --all-databases > wiki-mysql-backup.sql

# Backup persistent data
kubectl cp wiki-mysql-pod:/var/lib/mysql wiki-mysql-data/
```

### **Performance Monitoring**

**Resource Monitoring**
```bash
# Monitor cluster resources
kubectl top nodes
kubectl top pods -A

# Check resource limits
kubectl describe nodes | grep -A 5 "Allocated resources"

# Monitor specific pod
kubectl exec deployment/wiki-web -n wetfish-dev -- top
```

---

## 🔍 Log Analysis

### **Useful Log Queries**

**Application Logs**
```bash
# Get recent logs
kubectl logs deployment/wiki-web -n wetfish-dev --tail=100

# Follow logs in real-time
kubectl logs deployment/wiki-web -n wetfish-dev -f

# Get logs from specific time
kubectl logs deployment/wiki-web -n wetfish-dev --since=1h

# Get previous container logs
kubectl logs deployment/wiki-web -n wetfish-dev --previous
```

**System Logs**
```bash
# Get all pod logs
kubectl get pods -A | awk '{print $1,$2}' | while read ns pod; do
  echo "=== $ns/$pod ==="
  kubectl logs $pod -n $ns --tail=5
done

# Get events
kubectl get events -A --sort-by=.metadata.creationTimestamp

# Get specific resource events
kubectl get events -n wetfish-dev --field-selector involvedObject.name=wiki
```

---

## 📞 Getting Help

### **Information Gathering**
When reporting issues, collect this information:

```bash
# System information
k3d version
kubectl version
docker version
uname -a

# Cluster status
kubectl cluster-info
kubectl get nodes -o wide
kubectl get pods -A

# Resource status
kubectl top nodes
kubectl top pods -A

# Recent events
kubectl get events -A --sort-by=.metadata.creationTimestamp | tail -20
```

### **Debugging Workflow**
1. **Identify the scope** (cluster, namespace, pod, container)
2. **Check health status** (get/describe commands)
3. **Review logs** (pod logs, events)
4. **Test connectivity** (network, DNS)
5. **Verify configuration** (resources, secrets, configmaps)
6. **Isolate the issue** (reproduce in minimal environment)
7. **Document findings** (for future reference and team knowledge)

---

### **Common Solutions Summary**

| Problem | Quick Fix | Long Term Fix |
|---------|-----------|---------------|
| Pod pending | Check resources | Set proper limits/requests |
| Service not reachable | Check labels | Implement health checks |
| Ingress 404 | Verify DNS | Set up external DNS |
| Database connection fails | Check credentials | Use secrets management |
| No monitoring data | Check ServiceMonitor | Automate metrics discovery |
| Slow performance | Check resource limits | Implement HPA |
| Deployment fails | Rollback | Implement canary deployments |

---

*Troubleshooting Guide v1.0 - Last Updated: $(date)*