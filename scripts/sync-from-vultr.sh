#!/usr/bin/env bash
# Incremental sync: vultr-prod → FishStack-k3d prod
# DB:      mysqldump piped directly into k8s pod (no disk hit)
# Uploads: rsync straight into local-path PVC hostPath (incremental, no staging)
set -euo pipefail

# cron runs with a minimal PATH; kubectl lives outside /usr/bin
export PATH="/usr/local/bin:/usr/bin:/bin:/opt/bin:$PATH"
export KUBECONFIG="${KUBECONFIG:-/etc/rancher/k3s/k3s.yaml}"

VULTR_HOST="root@149.28.239.165"
VULTR_KEY="/root/.ssh/cyba_wetish"
NAMESPACE="wetfish-prod"

log() { echo "[$(date -u +%Y-%m-%dT%H:%M:%SZ)] $*"; }

# SAFETY GUARD — this script OVERWRITES production databases with stale
# old-prod (149.28.239.165) data. It was only valid BEFORE the 2026-08-17
# DNS cutover; afterwards it silently destroys fresh prod data every run
# (see docs/incidents/2026-08-22-wiki-db-overwrite.md).
#
# Post-cutover, old-prod is frozen rollback-only. Running this without the
# explicit opt-in flag below is almost certainly a mistake.
if [[ "${1:-}" != "--force-post-cutover" ]]; then
  log "REFUSING to run: this pulls STALE data from old-prod and overwrites k3s prod DBs."
  log "The DNS cutover happened 2026-08-17; old-prod no longer receives updates."
  log "If you REALLY intend to overwrite prod with stale data, pass --force-post-cutover."
  exit 1
fi

# Resolve the wiki-uploads PVC hostPath dynamically (was hardcoded to a stale path)
uploads_pvc_path() {
  local vol
  vol=$(kubectl -n "$NAMESPACE" get pvc wiki-uploads-pvc -o jsonpath='{.spec.volumeName}' 2>/dev/null)
  [ -n "$vol" ] || { log "ERROR: wiki-uploads-pvc not found"; exit 1; }
  kubectl get pv "$vol" -o jsonpath='{.spec.local.path}'
}

# --- DB sync ---
log "Starting wiki DB sync"
WIKI_MYSQL_POD=$(kubectl get pod -n "$NAMESPACE" -l app=wiki,component=mysql -o jsonpath='{.items[0].metadata.name}')
WIKI_MYSQL_PASS=$(kubectl get secret -n "$NAMESPACE" wiki-mysql-secret -o jsonpath='{.data.mysql-root-password}' | base64 -d)

ssh -i "$VULTR_KEY" -o StrictHostKeyChecking=no "$VULTR_HOST" \
  "docker exec wiki-db mysqldump -u root -pBcTiXoviFhlpnPiE4ynutVAR1x8DZaI9 --single-transaction --quick wiki" \
  | kubectl exec -i -n "$NAMESPACE" "$WIKI_MYSQL_POD" -- \
    sh -c "mysql -u root -p\"${WIKI_MYSQL_PASS}\" wikidb"

log "DB sync complete"

# --- Uploads rsync ---
log "Starting wiki uploads rsync"
UPLOADS_PVC_PATH=$(uploads_pvc_path)

# NOTE: --delete omitted — additive sync only, never removes data on the k3s side.
rsync -az --info=stats2 \
  -e "ssh -i $VULTR_KEY -o StrictHostKeyChecking=no" \
  "$VULTR_HOST:/mnt/wetfish/wiki/uploads/" \
  "$UPLOADS_PVC_PATH/"

log "Uploads rsync complete"

# --- Disk check ---
DISK_USE=$(df -h / | awk 'NR==2{print $5}' | tr -d '%')
if [ "$DISK_USE" -gt 80 ]; then
  log "WARNING: disk usage at ${DISK_USE}% — investigate before next sync"
fi

log "Done"
