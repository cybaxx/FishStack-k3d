#!/usr/bin/env bash
# Incremental sync: vultr-prod → FishStack-k3d prod
# DB:      mysqldump piped directly into k8s pod (no disk hit)
# Uploads: rsync straight into local-path PVC hostPath (incremental, no staging)
set -euo pipefail

VULTR_HOST="root@149.28.239.165"
VULTR_KEY="/root/.ssh/cyba_wetish"
NAMESPACE="wetfish-prod"
UPLOADS_PVC_PATH="/var/lib/rancher/k3s/storage/pvc-cba80cd4-f176-440b-a0fc-5e2350358add_wetfish-prod_wiki-uploads-pvc"

log() { echo "[$(date -u +%Y-%m-%dT%H:%M:%SZ)] $*"; }

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

rsync -az --delete --info=stats2 \
  -e "ssh -i $VULTR_KEY -o StrictHostKeyChecking=no" \
  "$VULTR_HOST:/opt/web-services/prod/services/wiki/upload/" \
  "$UPLOADS_PVC_PATH/"

log "Uploads rsync complete"

# --- Disk check ---
DISK_USE=$(df -h / | awk 'NR==2{print $5}' | tr -d '%')
if [ "$DISK_USE" -gt 80 ]; then
  log "WARNING: disk usage at ${DISK_USE}% — investigate before next sync"
fi

log "Done"
