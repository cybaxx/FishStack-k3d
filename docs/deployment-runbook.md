# Deployment Runbook - Staging & Production

> Operational guide for deploying wetfish services to staging and production environments.

---

## Environment Overview

| | Staging | Production |
|---|---------|------------|
| **Server** | `ssh stage` (Debian 12 VPS, 1 vCPU, 1GB RAM) | TBD |
| **Cluster** | k3s single-node (`--disable=traefik`) | TBD |
| **Branch** | `main` | `release` |
| **Namespace** | `wetfish-staging` | `wetfish-prod` |
| **Hostnames** | `staging-<svc>.wetfish.net` / `staging.wetfish.net` | `<svc>.wetfish.net` / `wetfish.net` |
| **Registry** | `ghcr.io/cybaxx/web-services-k8s` | `ghcr.io/cybaxx/web-services-k8s` |
| **Image tags** | `staging-<component>` | `prod-<component>` |
| **TLS** | Traefik built-in ACME (behind Cloudflare proxy) | Traefik built-in ACME (behind Cloudflare proxy) |
| **DNS** | Cloudflare proxied (orange cloud) | Cloudflare proxied (orange cloud) |

### Services

| Service | Components | Has DB | Has SITE_URL | Staging Status |
|---------|-----------|--------|-------------|----------------|
| wiki | nginx, php | Yes (MariaDB) | Yes | Deployed |
| home | app | No | No | Pending (no GHCR image yet) |
| glitch | nginx, php | No | No | Not deployed (RAM constrained) |
| click | nginx, php | Yes (MariaDB) | No | Not deployed (RAM constrained) |
| danger | nginx, php | Yes (MariaDB) | Yes | Not deployed (RAM constrained) |

> **Note:** The staging server has only 1GB RAM. Currently only wiki is deployed. Adding more services requires a larger VPS or careful memory tuning.

---

## Staging Server Setup (One-Time)

### 1. Install k3s

```bash
ssh stage "curl -sfL https://get.k3s.io | INSTALL_K3S_EXEC='--disable=traefik' sh -"
ssh stage "mkdir -p ~/.kube && cp /etc/rancher/k3s/k3s.yaml ~/.kube/config && chmod 600 ~/.kube/config"
```

k3s includes kubectl, local-path storage provisioner, and CoreDNS. Built-in Traefik is disabled because we deploy our own.

### 2. Install Helm

```bash
ssh stage "curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash"
```

### 3. Clone/Update Repo

```bash
ssh stage "cd /opt && git clone --recurse-submodules ssh://github.com/cybaxx/web-services-k8s.git"
# Or if already cloned:
ssh stage "cd /opt/web-services-k8s && git pull && git submodule update --init"
```

### 4. Deploy Infrastructure

```bash
ssh stage "cd /opt/web-services-k8s && kubectl apply -f infrastructure/namespaces.yaml"

# cert-manager (for future use / fallback)
ssh stage "helm repo add jetstack https://charts.jetstack.io && helm repo update jetstack"
ssh stage "helm install cert-manager jetstack/cert-manager --namespace cert-manager --create-namespace --set crds.enabled=true"
ssh stage "kubectl apply -f infrastructure/cert-manager/cluster-issuer.yaml -f infrastructure/cert-manager/letsencrypt-issuer.yaml"

# Traefik (with built-in ACME for Let's Encrypt)
ssh stage "kubectl apply -f infrastructure/traefik/ingressclass.yaml -f infrastructure/traefik/deployment.yaml"
```

### 5. Verify Infrastructure

```bash
ssh stage "kubectl get pods -n wetfish-system"        # Traefik running
ssh stage "kubectl get pods -n cert-manager"           # cert-manager running
ssh stage "kubectl get svc traefik -n wetfish-system"  # External IP assigned, ports 80/443
```

---

## Prerequisites

### Tools Required
```bash
kubectl          # Kubernetes CLI (included with k3s)
helm             # Helm package manager
```

### TLS / Cloudflare

TLS is handled by Traefik's built-in ACME resolver with HTTP-01 challenges. Services sit behind Cloudflare proxy (orange cloud), which forwards ACME challenges to the origin server.

Staging ingress patches use these Traefik annotations instead of cert-manager:
```yaml
annotations:
  traefik.ingress.kubernetes.io/router.tls.certresolver: letsencrypt
  traefik.ingress.kubernetes.io/router.entrypoints: websecure
spec:
  ingressClassName: traefik
```

> **Important:** Do NOT use `cert-manager.io/cluster-issuer` annotations on staging/prod ingresses. Traefik's built-in ACME and cert-manager will conflict if both try to manage certificates for the same domain.

---

## Staging Deployment

### 1. CI/CD - Automatic Image Build

Images are built automatically by GitHub Actions when code is pushed to `main`.

Each service has a trigger workflow (e.g., `build-wiki.yml`) that calls the reusable `build-service.yml` workflow. Images are pushed to GHCR with `staging-<component>` tags.

```bash
# Verify images are pullable from the stage server
ssh stage "crictl pull ghcr.io/cybaxx/web-services-k8s/wiki:staging-nginx"
ssh stage "crictl pull ghcr.io/cybaxx/web-services-k8s/wiki:staging-php"
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
# On the stage server — generate-secrets.sh may hit SIGPIPE on Linux,
# so generate manually if needed:
ssh stage 'bash -c '\''
b64() { echo -n "$1" | base64; }
ROOT_PASS=$(openssl rand -base64 18)
USER_PASS=$(openssl rand -base64 18)
# ... (see scripts/generate-secrets.sh for full template)
'\'''
```

After generating, add `secret.yaml` to the kustomization if not already present:
```bash
# Check and add if missing
ssh stage "grep -q secret.yaml services/wiki/k8s/overlays/staging/kustomization.yaml || \
  sed -i '/- ..\/..\/base/a\  - secret.yaml' services/wiki/k8s/overlays/staging/kustomization.yaml"
```

> **Important:** Save the generated passwords securely. You'll need the MySQL root passwords for schema loading.

### 3. Deploy Services

```bash
ssh stage "cd /opt/web-services-k8s && ./scripts/deploy.sh --env staging wiki"
```

> **Note:** ServiceMonitor CRD warnings are expected (no monitoring stack on staging). These are harmless.

### 4. Load DB Schemas (First Deploy Only)

```bash
# Get the root password from the secret
ssh stage 'ROOT_PASS=$(kubectl get secret wiki-mysql-secret -n wetfish-staging \
  -o jsonpath="{.data.mysql-root-password}" | base64 -d) && \
  kubectl exec -i deployment/wiki-mysql -n wetfish-staging -- \
  mysql -uroot -p"${ROOT_PASS}" wikidb < /opt/web-services-k8s/services/wiki/src/wwwroot/src/schema.sql'
```

### 5. Verify Deployment

```bash
# Check pods
ssh stage "kubectl get pods -n wetfish-staging"

# Check ingress
ssh stage "kubectl get ingress -n wetfish-staging"

# Test via HTTPS (through Cloudflare)
curl -s -o /dev/null -w "staging-wiki.wetfish.net -> HTTP %{http_code}\n" \
  https://staging-wiki.wetfish.net

# Test locally on the server (bypassing Cloudflare)
ssh stage 'curl -s -o /dev/null -w "%{http_code}" \
  --resolve "staging-wiki.wetfish.net:80:127.0.0.1" \
  http://staging-wiki.wetfish.net/'
```

### 6. Updating Deployments

After pushing changes to `main` and CI builds new images:

```bash
ssh stage "cd /opt/web-services-k8s && git pull && ./scripts/deploy.sh --env staging wiki"
# k3s will pull the latest image with the staging-* tag
```

To force a re-pull if the tag hasn't changed:
```bash
ssh stage "kubectl rollout restart deployment/wiki-web -n wetfish-staging"
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

Wait for GitHub Actions to complete.

| Service | Image Tags |
|---------|-----------|
| wiki | `prod-nginx`, `prod-php` |
| home | `prod-app` |
| glitch | `prod-nginx`, `prod-php` |
| click | `prod-nginx`, `prod-php` |
| danger | `prod-nginx`, `prod-php` |

### 2. Generate Secrets

```bash
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

# Test endpoints
for svc in wiki glitch click danger; do
  curl -s -o /dev/null -w "$svc.wetfish.net -> HTTP %{http_code}\n" \
    https://$svc.wetfish.net
done
# Home is at wetfish.net (no prefix)
curl -s -o /dev/null -w "wetfish.net -> HTTP %{http_code}\n" \
  https://wetfish.net
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

# Diff against what's currently deployed
kubectl diff -k services/wiki/k8s/overlays/staging/
```

---

## Troubleshooting

### Common Issues

| Symptom | Cause | Fix |
|---------|-------|-----|
| `ImagePullBackOff` | GHCR image not found | Check GitHub Actions completed; verify with `crictl pull` on server |
| `CreateContainerConfigError` | Missing secret | Generate secret.yaml and add to kustomization.yaml |
| Wiki returns 500 | DB schema not loaded | Load schema per instructions above |
| ACME cert not issued | Cloudflare proxy blocking challenge | Verify Cloudflare forwards to correct origin IP; check Traefik logs |
| ServiceMonitor warnings | No monitoring CRDs on staging | Harmless — ignore |
| MySQL `CrashLoopBackOff` | Corrupted PVC data | Delete PVC, redeploy, reload schema |
| `generate-secrets.sh` exits 141 | SIGPIPE from `tr \| head` on Linux | Fixed in latest; or generate secrets manually |

### Useful Debug Commands

```bash
# Pod logs
ssh stage "kubectl logs deployment/wiki-web -n wetfish-staging -c nginx -f"
ssh stage "kubectl logs deployment/wiki-web -n wetfish-staging -c php-fpm -f"
ssh stage "kubectl logs deployment/wiki-mysql -n wetfish-staging -f"
ssh stage "kubectl logs deployment/traefik -n wetfish-system --tail=20"

# Shell into a container
ssh stage "kubectl exec -it deployment/wiki-web -n wetfish-staging -c php-fpm -- bash"

# Check events
ssh stage "kubectl get events -n wetfish-staging --sort-by=.metadata.creationTimestamp | tail -20"

# Check memory usage (important on 1GB server)
ssh stage "free -h"
ssh stage "kubectl top pods -n wetfish-staging"
```

See `docs/troubleshooting.md` for more detailed troubleshooting guidance.
