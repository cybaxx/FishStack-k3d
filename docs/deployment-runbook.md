# Deployment Runbook - Staging & Production

> Operational guide for deploying wetfish services to staging and production environments.

---

## Environment Overview

| | Staging | Production |
|---|---------|------------|
| **Branch** | `main` | `release` |
| **Namespace** | `wetfish-staging` | `wetfish-prod` |
| **Hostnames** | `*.staging.wetfish.net` | `*.wetfish.net` |
| **Registry** | `ghcr.io/cybaxx/web-services-k8s` | `ghcr.io/cybaxx/web-services-k8s` |
| **Image tags** | `staging-<component>` | `prod-<component>` |
| **TLS** | cert-manager (Let's Encrypt) | cert-manager (Let's Encrypt) |

### Services

| Service | Components | Has DB | Has SITE_URL |
|---------|-----------|--------|-------------|
| wiki | nginx, php | Yes (MariaDB) | Yes |
| home | app | No | No |
| glitch | nginx, php | No | No |
| click | nginx, php | Yes (MariaDB) | No |
| danger | nginx, php | Yes (MariaDB) | Yes |

---

## Prerequisites

### Tools Required
```bash
kubectl          # Kubernetes CLI
helm             # Helm package manager (for monitoring/cert-manager)
gh               # GitHub CLI (optional, for checking workflow status)
```

### Cluster Access
Ensure your kubeconfig is pointed at the correct cluster and you have write access to the target namespace.

```bash
# Verify cluster access
kubectl cluster-info
kubectl get namespace wetfish-staging
kubectl get namespace wetfish-prod
```

### Namespaces
Namespaces must exist before deploying. If not:
```bash
kubectl apply -f infrastructure/namespaces.yaml
```

### cert-manager
TLS certificates are managed by cert-manager. Verify it's installed:
```bash
kubectl get pods -n cert-manager
kubectl get clusterissuer
```

If missing, deploy it:
```bash
./scripts/deploy.sh cert-manager
```

> **Note:** The staging/prod ingress patches reference a `wetfish-letsencrypt` ClusterIssuer for ACME/Let's Encrypt certificates. Ensure this issuer is configured for your cluster. The default `wetfish-selfsigned` issuer is for dev only.

---

## Staging Deployment

### 1. CI/CD - Automatic Image Build

Images are built automatically by GitHub Actions when code is pushed to `main`.

Each service has a trigger workflow (e.g., `build-wiki.yml`) that calls the reusable `build-service.yml` workflow. Images are pushed to GHCR with `staging-<component>` tags.

```bash
# Check if images were built for latest main commit
gh run list --branch main --limit 5

# Verify images exist in GHCR
docker pull ghcr.io/cybaxx/web-services-k8s/wiki:staging-nginx
docker pull ghcr.io/cybaxx/web-services-k8s/wiki:staging-php
```

| Service | Image Tags |
|---------|-----------|
| wiki | `staging-nginx`, `staging-php` |
| home | `staging-app` |
| glitch | `staging-nginx`, `staging-php` |
| click | `staging-nginx`, `staging-php` |
| danger | `staging-nginx`, `staging-php` |

### 2. Generate Secrets

Secrets must be generated before first deploy. They are gitignored and stored locally in the overlay directory.

```bash
# Generate with random passwords (recommended for staging)
./scripts/generate-secrets.sh --env staging --random
```

This creates secret files for services with databases:
- `services/wiki/k8s/overlays/staging/secret.yaml`
- `services/click/k8s/overlays/staging/secret.yaml`
- `services/danger/k8s/overlays/staging/secret.yaml`

> **Important:** Save the generated passwords securely. You'll need the MySQL root passwords for schema loading.

### 3. Deploy Services

```bash
# Deploy all services
./scripts/deploy.sh --env staging wiki
./scripts/deploy.sh --env staging home
./scripts/deploy.sh --env staging glitch
./scripts/deploy.sh --env staging click
./scripts/deploy.sh --env staging danger
```

Or deploy a single service:
```bash
./scripts/deploy.sh --env staging wiki
```

### 4. Verify Deployment

```bash
# Check all pods
kubectl get pods -n wetfish-staging

# Check ingresses
kubectl get ingress -n wetfish-staging

# Check TLS certificates
kubectl get certificates -n wetfish-staging
```

Expected output - all pods Running, all ingresses with hosts assigned:
```
wiki-web-xxx        2/2   Running
wiki-mysql-xxx      1/1   Running
home-web-xxx        1/1   Running
glitch-web-xxx      2/2   Running
click-web-xxx       2/2   Running
click-mysql-xxx     1/1   Running
danger-web-xxx      2/2   Running
danger-mysql-xxx    1/1   Running
```

### 5. Load DB Schemas (First Deploy Only)

On first deploy, database schemas must be loaded manually. Replace passwords with the ones generated in step 2.

```bash
# Wiki
kubectl exec -i deployment/wiki-mysql -n wetfish-staging -- \
  mysql -uroot -p<WIKI_ROOT_PASSWORD> wikidb < services/wiki/src/wwwroot/src/schema.sql

# Click
kubectl exec -i deployment/click-mysql -n wetfish-staging -- \
  mysql -uroot -p<CLICK_ROOT_PASSWORD> clickdb < services/click/src/schema.sql

# Danger
kubectl exec -i deployment/danger-mysql -n wetfish-staging -- \
  mysql -uroot -p<DANGER_ROOT_PASSWORD> dangerdb < services/danger/src/schema.sql
```

### 6. Smoke Test

```bash
# Test each service endpoint
for svc in wiki home glitch click danger; do
  curl -s -o /dev/null -w "$svc.staging.wetfish.net -> HTTP %{http_code}\n" \
    https://$svc.staging.wetfish.net
done
```

---

## Production Deployment

### 1. Promote to Release Branch

Production images are built when code is pushed to the `release` branch.

```bash
# Merge main into release
git checkout release
git merge main
git push origin release
```

Wait for GitHub Actions to complete. Verify:
```bash
gh run list --branch release --limit 5
```

| Service | Image Tags |
|---------|-----------|
| wiki | `prod-nginx`, `prod-php` |
| home | `prod-app` |
| glitch | `prod-nginx`, `prod-php` |
| click | `prod-nginx`, `prod-php` |
| danger | `prod-nginx`, `prod-php` |

### 2. Generate Secrets

```bash
# Generate with random passwords (required for production)
./scripts/generate-secrets.sh --env prod --random
```

> **Critical:** Store production passwords in a secure vault. These cannot be recovered if lost.

### 3. Pre-Deploy Checklist

Before deploying to production:

- [ ] All changes tested in staging
- [ ] GitHub Actions workflows completed successfully on `release` branch
- [ ] Secrets generated for prod environment
- [ ] Database backups taken (if updating existing deployment)
- [ ] Rollback plan documented
- [ ] Team notified of deployment window

### 4. Deploy Services

```bash
# Deploy one service at a time, verify between each
./scripts/deploy.sh --env prod wiki
kubectl rollout status deployment/wiki-web -n wetfish-prod --timeout=300s
kubectl rollout status deployment/wiki-mysql -n wetfish-prod --timeout=300s

./scripts/deploy.sh --env prod home
kubectl rollout status deployment/home-web -n wetfish-prod --timeout=300s

./scripts/deploy.sh --env prod glitch
kubectl rollout status deployment/glitch-web -n wetfish-prod --timeout=300s

./scripts/deploy.sh --env prod click
kubectl rollout status deployment/click-web -n wetfish-prod --timeout=300s
kubectl rollout status deployment/click-mysql -n wetfish-prod --timeout=300s

./scripts/deploy.sh --env prod danger
kubectl rollout status deployment/danger-web -n wetfish-prod --timeout=300s
kubectl rollout status deployment/danger-mysql -n wetfish-prod --timeout=300s
```

### 5. Load DB Schemas (First Deploy Only)

```bash
kubectl exec -i deployment/wiki-mysql -n wetfish-prod -- \
  mysql -uroot -p<WIKI_ROOT_PASSWORD> wikidb < services/wiki/src/wwwroot/src/schema.sql

kubectl exec -i deployment/click-mysql -n wetfish-prod -- \
  mysql -uroot -p<CLICK_ROOT_PASSWORD> clickdb < services/click/src/schema.sql

kubectl exec -i deployment/danger-mysql -n wetfish-prod -- \
  mysql -uroot -p<DANGER_ROOT_PASSWORD> dangerdb < services/danger/src/schema.sql
```

### 6. Verify Production

```bash
# Check all pods
kubectl get pods -n wetfish-prod

# Check TLS certificates are issued
kubectl get certificates -n wetfish-prod

# Test endpoints
for svc in wiki home glitch click danger; do
  curl -s -o /dev/null -w "$svc.wetfish.net -> HTTP %{http_code}\n" \
    https://$svc.wetfish.net
done
```

---

## Rollback

### Quick Rollback (Kubernetes)

Roll back a deployment to its previous revision:

```bash
# Rollback a single service
kubectl rollout undo deployment/wiki-web -n wetfish-prod
kubectl rollout undo deployment/wiki-mysql -n wetfish-prod

# Verify rollback
kubectl rollout status deployment/wiki-web -n wetfish-prod
```

### Full Rollback (Redeploy Previous Image)

If you need to deploy a specific previous image version:

```bash
# List available image tags
gh api /orgs/cybaxx/packages/container/web-services-k8s%2Fwiki/versions \
  --jq '.[].metadata.container.tags[]' | head -20

# Set a specific image
kubectl set image deployment/wiki-web \
  nginx=ghcr.io/cybaxx/web-services-k8s/wiki:prod-nginx \
  php-fpm=ghcr.io/cybaxx/web-services-k8s/wiki:prod-php \
  -n wetfish-prod
```

### Delete and Redeploy

Nuclear option - remove everything and start fresh:

```bash
./scripts/deploy.sh --env prod wiki delete
./scripts/deploy.sh --env prod wiki
```

> **Warning:** This deletes PVCs. Database data will be lost unless backed up first.

---

## Database Operations

### Backup

```bash
# Backup wiki database
kubectl exec deployment/wiki-mysql -n wetfish-prod -- \
  mysqldump -uroot -p<PASSWORD> --single-transaction wikidb > wiki-backup-$(date +%Y%m%d).sql

# Backup click database
kubectl exec deployment/click-mysql -n wetfish-prod -- \
  mysqldump -uroot -p<PASSWORD> --single-transaction clickdb > click-backup-$(date +%Y%m%d).sql

# Backup danger database
kubectl exec deployment/danger-mysql -n wetfish-prod -- \
  mysqldump -uroot -p<PASSWORD> --single-transaction dangerdb > danger-backup-$(date +%Y%m%d).sql
```

### Restore

```bash
kubectl exec -i deployment/wiki-mysql -n wetfish-prod -- \
  mysql -uroot -p<PASSWORD> wikidb < wiki-backup-20260218.sql
```

---

## Monitoring (Optional)

Deploy the monitoring stack to any environment:

```bash
./scripts/deploy.sh monitoring
```

This installs Prometheus, Grafana, Loki, Tempo, and Promtail into `wetfish-monitoring`. Access Grafana at `grafana.wetfish.local:8080` (dev) or configure ingress for staging/prod.

---

## Kustomize Dry Run

Preview what will be deployed without applying:

```bash
# Preview staging manifests
kubectl kustomize services/wiki/k8s/overlays/staging/

# Preview prod manifests
kubectl kustomize services/wiki/k8s/overlays/prod/

# Diff against what's currently deployed
kubectl diff -k services/wiki/k8s/overlays/staging/
```

---

## Troubleshooting

### Common Issues

| Symptom | Cause | Fix |
|---------|-------|-----|
| `ImagePullBackOff` | GHCR image not found | Check GitHub Actions completed; verify image tag exists |
| `CreateContainerConfigError` | Missing secret | Run `generate-secrets.sh --env <env>` and redeploy |
| Wiki returns 500 | DB schema not loaded | Load schema per instructions above |
| TLS certificate not issued | cert-manager misconfigured | Check `kubectl describe certificate -n <ns>` and ClusterIssuer |
| MySQL `CrashLoopBackOff` | Corrupted PVC data | Delete PVC, redeploy, reload schema |

### Useful Debug Commands

```bash
# Pod logs
kubectl logs deployment/wiki-web -n wetfish-staging -c nginx -f
kubectl logs deployment/wiki-web -n wetfish-staging -c php-fpm -f
kubectl logs deployment/wiki-mysql -n wetfish-staging -f

# Shell into a container
kubectl exec -it deployment/wiki-web -n wetfish-staging -c php-fpm -- bash

# Check events
kubectl get events -n wetfish-staging --sort-by=.metadata.creationTimestamp | tail -20

# Check resource usage
kubectl top pods -n wetfish-staging
```

See `docs/troubleshooting.md` for more detailed troubleshooting guidance.
