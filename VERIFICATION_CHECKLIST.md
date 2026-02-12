# Verification Checklist - Phase 1-4 Implementation

Use this checklist to verify all implementation phases are complete and correct.

## Phase 1: Critical Fixes

### 1.1 GitHub Actions Workflows
- [x] `.github/workflows/build-wiki-nginx.yml` exists at repo root
- [x] `.github/workflows/build-wiki-php.yml` exists at repo root
- [x] Both workflows have `context: services/wiki` (not `.`)
- [x] Both workflows have path filters for `services/wiki/**`
- [x] Image names are `ghcr.io/cybaxx/web-services-k8s/wiki:*-nginx` and `*-php`
- [x] Workflows trigger on push to main/release

**Verification command:**
```bash
ls -la .github/workflows/build-wiki-*.yml
grep "context: services/wiki" .github/workflows/build-wiki-*.yml
```

### 1.2 Wiki K8s Manifests
- [x] `services/wiki/k8s/01-configmap.yaml` contains nginx + PHP configs
- [x] `services/wiki/k8s/05-web.yaml` exists (new sidecar deployment)
- [x] `services/wiki/k8s/06-ingress.yaml` points to `wiki-web` service
- [x] `services/wiki/k8s/07-monitoring.yaml` monitors `wiki-web` component
- [x] `services/wiki/k8s/05-mediawiki.yaml` removed
- [x] `services/wiki/k8s/08-install.yaml` removed

**Verification command:**
```bash
ls -1 services/wiki/k8s/
grep "wiki-web" services/wiki/k8s/06-ingress.yaml
grep "nginx" services/wiki/k8s/05-web.yaml | grep "php-fpm"
```

**Check sidecar pattern:**
```bash
grep -A 5 "containers:" services/wiki/k8s/05-web.yaml | head -15
# Should show both nginx and php-fpm containers
```

### 1.3 Scripts Fixed
- [x] `scripts/setup-dev.sh` auto-detects PROJECT_DIR
- [x] `scripts/setup-dev.sh` checks for helm
- [x] `scripts/deploy.sh` auto-detects PROJECT_DIR
- [x] `scripts/cleanup.sh` auto-detects PROJECT_DIR

**Verification command:**
```bash
grep 'SCRIPT_DIR.*pwd' scripts/setup-dev.sh scripts/deploy.sh scripts/cleanup.sh
grep 'helm' scripts/setup-dev.sh
```

## Phase 2: Monitoring Setup

### 2.1 Helm Values Files
- [x] `monitoring/values/prometheus-stack-values.yaml` exists
- [x] `monitoring/values/loki-values.yaml` exists
- [x] `monitoring/values/tempo-values.yaml` exists
- [x] All values files have ingress hosts configured
- [x] All values files have storage configuration

**Verification command:**
```bash
ls -1 monitoring/values/
grep "ingress:" monitoring/values/*.yaml
grep "storage" monitoring/values/*.yaml
```

### 2.2 Deploy.sh Monitoring Function
- [x] Uses `helm upgrade --install` (not `helm install`)
- [x] References values files from `${PROJECT_DIR}/monitoring/values/`
- [x] Has `--wait --timeout 10m` flags
- [x] Shows access URLs after deployment

**Verification command:**
```bash
grep "helm upgrade --install" scripts/deploy.sh
grep "monitoring/values/" scripts/deploy.sh
grep "Access URLs" scripts/deploy.sh
```

## Phase 3: DNS & Testing

### 3.1 Setup Hosts Script
- [x] `scripts/setup-hosts.sh` exists
- [x] Contains all required hosts (wiki, grafana, prometheus, etc.)
- [x] Has add/remove/show/verify commands
- [x] Uses marker comments for managed section
- [x] Requires sudo

**Verification command:**
```bash
ls -la scripts/setup-hosts.sh
grep "wiki.wetfish.local" scripts/setup-hosts.sh
grep "BEGIN wetfish-k8s" scripts/setup-hosts.sh
grep "EUID" scripts/setup-hosts.sh
```

**Test the script:**
```bash
./scripts/setup-hosts.sh show  # Should work without sudo
./scripts/setup-hosts.sh -h    # Should show help
```

### 3.2 Test Deployment Script
- [x] `scripts/test-deployment.sh` exists
- [x] Has all 5 test suites (pods, services, ingress, HTTP, logs)
- [x] Accepts namespace and service parameters
- [x] Returns exit code 1 on failure
- [x] Color-coded output

**Verification command:**
```bash
ls -la scripts/test-deployment.sh
grep "TEST 1:" scripts/test-deployment.sh
grep "TEST 5:" scripts/test-deployment.sh
./scripts/test-deployment.sh -h  # Should show usage
```

## Phase 4: Documentation

### 4.1 CLAUDE.md
- [x] Says "custom PHP application" (not "MediaWiki")
- [x] References `wiki-web` deployment (not `wiki-mediawiki`)
- [x] Shows sidecar container commands (`-c nginx`, `-c php-fpm`)
- [x] Includes `setup-hosts.sh` in lifecycle commands
- [x] Includes `test-deployment.sh` in debugging commands

**Verification command:**
```bash
grep "custom PHP" CLAUDE.md
grep "wiki-web" CLAUDE.md
grep "setup-hosts.sh" CLAUDE.md
grep "test-deployment.sh" CLAUDE.md
grep -- "-c php-fpm" CLAUDE.md
```

### 4.2 README.md
- [x] Prerequisites include `helm`
- [x] Quick Start includes `setup-hosts.sh`
- [x] Shows sidecar container log commands
- [x] References `wiki-web` deployment (not `wiki`)
- [x] Says "custom PHP application" (not "MediaWiki")

**Verification command:**
```bash
grep "helm" README.md
grep "setup-hosts.sh" README.md
grep "wiki-web" README.md
grep "custom PHP" README.md
grep -- "-c nginx" README.md
```

### 4.3 Architecture Docs
- [x] `docs/architecture-design.md` describes custom PHP app
- [x] Mentions sidecar pattern
- [x] Lists PVCs (wwwroot, uploads)
- [x] Lists ConfigMaps (nginx.conf, php.ini, php-fpm-pool.conf)

**Verification command:**
```bash
grep "sidecar" docs/architecture-design.md
grep "wwwroot" docs/architecture-design.md
grep "ConfigMaps:" docs/architecture-design.md
```

## File Integrity Check

### New Files Created
```bash
# These files should exist:
test -f .github/workflows/build-wiki-nginx.yml && echo "✓ nginx workflow"
test -f .github/workflows/build-wiki-php.yml && echo "✓ php workflow"
test -f services/wiki/k8s/05-web.yaml && echo "✓ web deployment"
test -f monitoring/values/prometheus-stack-values.yaml && echo "✓ prometheus values"
test -f monitoring/values/loki-values.yaml && echo "✓ loki values"
test -f monitoring/values/tempo-values.yaml && echo "✓ tempo values"
test -f scripts/setup-hosts.sh && echo "✓ setup-hosts script"
test -f scripts/test-deployment.sh && echo "✓ test-deployment script"
test -f IMPLEMENTATION_SUMMARY.md && echo "✓ implementation summary"
test -f VERIFICATION_CHECKLIST.md && echo "✓ verification checklist"
```

### Files That Should NOT Exist
```bash
# These files should be deleted:
test ! -f services/wiki/k8s/05-mediawiki.yaml && echo "✓ mediawiki manifest removed"
test ! -f services/wiki/k8s/08-install.yaml && echo "✓ install job removed"
test ! -f services/wiki/.github/workflows/docker-autobuild-nginx.yml && echo "✓ old nginx workflow removed"
test ! -f services/wiki/.github/workflows/docker-autobuild-php.yml && echo "✓ old php workflow removed"
```

### Modified Files Check
```bash
# Check that files were modified (have recent timestamps):
ls -l services/wiki/k8s/01-configmap.yaml   # Should be recent
ls -l services/wiki/k8s/06-ingress.yaml     # Should be recent
ls -l services/wiki/k8s/07-monitoring.yaml  # Should be recent
ls -l scripts/setup-dev.sh                  # Should be recent
ls -l scripts/deploy.sh                     # Should be recent
ls -l scripts/cleanup.sh                    # Should be recent
ls -l CLAUDE.md                             # Should be recent
ls -l README.md                             # Should be recent
ls -l docs/architecture-design.md           # Should be recent
```

## Configuration Verification

### ConfigMap Contents
```bash
# Check ConfigMap has actual nginx config:
grep "listen 80;" services/wiki/k8s/01-configmap.yaml
grep "fastcgi_pass 127.0.0.1:9000;" services/wiki/k8s/01-configmap.yaml

# Check ConfigMap has PHP configs:
grep "php.ini:" services/wiki/k8s/01-configmap.yaml
grep "php-fpm-pool.conf:" services/wiki/k8s/01-configmap.yaml
```

### Deployment Sidecar Pattern
```bash
# Check deployment has both containers:
grep -A 2 "- name: nginx" services/wiki/k8s/05-web.yaml
grep -A 2 "- name: php-fpm" services/wiki/k8s/05-web.yaml

# Check init container:
grep -A 3 "initContainers:" services/wiki/k8s/05-web.yaml
```

### Helm Values Configuration
```bash
# Check Grafana ingress:
grep "grafana.wetfish.local" monitoring/values/prometheus-stack-values.yaml

# Check storage sizes:
grep "50Gi" monitoring/values/prometheus-stack-values.yaml  # Prometheus
grep "20Gi" monitoring/values/loki-values.yaml             # Loki
grep "10Gi" monitoring/values/tempo-values.yaml            # Tempo
```

## Script Functionality Tests

### Auto-Detection Test
```bash
# Run from different directory to test auto-detection:
cd /tmp
/Users/cyba/git/web-services-k8s/scripts/setup-hosts.sh show
# Should work without errors
```

### Helm Check Test
```bash
# Temporarily rename helm to test the check:
# (Don't actually do this if you need helm)
# The setup-dev.sh script should error if helm is missing
```

## Git Status Check

Run this to see what files were changed:
```bash
cd /Users/cyba/git/web-services-k8s
git status
```

Expected output should show:
- Modified: CLAUDE.md, README.md, docs/architecture-design.md
- Modified: services/wiki/k8s/*.yaml (several files)
- Modified: scripts/*.sh (several files)
- New: .github/workflows/build-wiki-*.yml
- New: services/wiki/k8s/05-web.yaml
- New: monitoring/values/*.yaml
- New: scripts/setup-hosts.sh
- New: scripts/test-deployment.sh
- New: IMPLEMENTATION_SUMMARY.md
- New: VERIFICATION_CHECKLIST.md
- Deleted: services/wiki/k8s/05-mediawiki.yaml
- Deleted: services/wiki/k8s/08-install.yaml

## Final Validation

Run all these commands to validate everything works:

```bash
# 1. Validate YAML syntax
for f in services/wiki/k8s/*.yaml monitoring/values/*.yaml .github/workflows/*.yml; do
    echo "Validating $f"
    yamllint -d relaxed "$f" || echo "Warning: yamllint not installed"
done

# 2. Validate script syntax
for f in scripts/*.sh; do
    echo "Validating $f"
    bash -n "$f"
done

# 3. Check executable permissions
ls -l scripts/*.sh
# setup-hosts.sh and test-deployment.sh should be executable

# 4. Grep for common mistakes
echo "Checking for hardcoded paths..."
grep -r "/Users/cyba" scripts/*.sh | grep -v "^#" | grep -v "Auto-detect"
# Should only show comments or PROJECT_DIR auto-detection

echo "Checking for MediaWiki references..."
grep -ri "mediawiki" services/wiki/k8s/*.yaml CLAUDE.md README.md docs/*.md
# Should return no results (except in IMPLEMENTATION_SUMMARY.md)

echo "Checking for old service names..."
grep -r "wiki-mediawiki" services/wiki/k8s/*.yaml CLAUDE.md README.md
# Should return no results (except in IMPLEMENTATION_SUMMARY.md)
```

## Success Criteria

ALL of the following must be true:

- ✅ All Phase 1 checklist items complete
- ✅ All Phase 2 checklist items complete
- ✅ All Phase 3 checklist items complete
- ✅ All Phase 4 checklist items complete
- ✅ All new files created
- ✅ All old files removed
- ✅ All modified files have correct content
- ✅ Scripts pass syntax validation
- ✅ YAML files pass syntax validation
- ✅ No hardcoded paths in scripts (except comments)
- ✅ No references to "MediaWiki" in live docs
- ✅ No references to "wiki-mediawiki" deployment

## Next Steps After Verification

Once all checks pass:

1. **Commit all changes:**
   ```bash
   git add .
   git status  # Review changes
   git commit -m "feat: implement all phases (workflows, manifests, monitoring, scripts, docs)"
   ```

2. **Test locally:**
   ```bash
   ./scripts/cleanup.sh
   ./scripts/setup-dev.sh
   sudo ./scripts/setup-hosts.sh
   ./scripts/deploy.sh wetfish-dev wiki
   ./scripts/test-deployment.sh wetfish-dev wiki
   ```

3. **Push to GitHub:**
   ```bash
   git push origin main
   # Or create a PR to main from a feature branch
   ```

4. **Verify GitHub Actions:**
   - Go to repository on GitHub
   - Check Actions tab
   - Verify workflows are recognized
   - Make a test commit to services/wiki/ to trigger builds

5. **Deploy monitoring:**
   ```bash
   ./scripts/deploy.sh wetfish-monitoring monitoring
   open http://grafana.wetfish.local
   ```

---

**If any check fails, refer to IMPLEMENTATION_SUMMARY.md for details on what should be in each file.**
