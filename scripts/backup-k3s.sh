#!/usr/bin/env bash
# backup-k3s.sh — Dump wetfish-prod databases + sync PVC data to S3 (vultr-s3)
# Runs ON the k3s server (216.128.155.242) via cron (every 6h).
# Mirrors the old-prod util/improved-backups.sh pattern, adapted for k3s.
#
#   DB:      mysqldump via kubectl exec  -> vultr-s3:wetfish-backups/databases/<date>/
#   Uploads: rclone sync wiki uploads PVC -> vultr-s3:wetfish-uploads
#   Forum:   rclone sync appdata+wwwroot  -> vultr-s3:wetfish-backups/forum-files/
#
# Non-destructive: dumps are additive to S3; local staging pruned after RETENTION_DAYS only.
set -euo pipefail

# cron runs with a minimal PATH; kubectl lives outside /usr/bin
export PATH="/usr/local/bin:/usr/bin:/bin:/opt/bin:$PATH"
export KUBECONFIG="${KUBECONFIG:-/etc/rancher/k3s/k3s.yaml}"

NAMESPACE="${NAMESPACE:-wetfish-prod}"
RCLONE_REMOTE="${RCLONE_REMOTE:-vultr-s3}"
DB_BUCKET="${DB_BUCKET:-wetfish-backups}"
UPLOADS_BUCKET="${UPLOADS_BUCKET:-wetfish-uploads}"
BACKUP_ROOT="${BACKUP_ROOT:-/var/backups/wetfish}"
RETENTION_DAYS="${RETENTION_DAYS:-7}"
TIMESTAMP=$(date +%Y-%m-%d)

# Vultr object storage rate-limits HEAD/object requests (HTTP 429) on many small
# files; keep concurrency modest and retry transient errors.
RCLONE_OPTS="--s3-no-check-bucket --transfers 4 --checkers 8 --retries 10 --low-level-retries 10"

log() { echo "[$(date -u +%Y-%m-%dT%H:%M:%SZ)] $*"; }

require_cmds() {
  # mysqldump runs inside the mysql pod (kubectl exec), not on the host
  for cmd in kubectl rclone sha256sum; do
    command -v "$cmd" >/dev/null 2>&1 || { log "ERROR: missing command: $cmd"; exit 1; }
  done
}

# service -> k8s mysql deployment | database name | secret name
# (mirrors old-prod DB names: wiki->wikidb, click->clickdb, fishy->dangerdb, forums->forumdb)
declare -A SERVICES=(
  [wiki]="wiki-mysql|wikidb|wiki-mysql-secret"
  [click]="click-mysql|clickdb|click-mysql-secret"
  [danger]="danger-mysql|dangerdb|danger-mysql-secret"
  [forum]="forum-mysql|forumdb|forum-mysql-secret"
)

mysql_root_pass() {
  local secret=$1
  kubectl -n "$NAMESPACE" get secret "$secret" \
    -o jsonpath='{.data.mysql-root-password}' | base64 -d
}

pvc_hostpath() {
  local pvc=$1
  local vol
  vol=$(kubectl -n "$NAMESPACE" get pvc "$pvc" -o jsonpath='{.spec.volumeName}' 2>/dev/null) || return 1
  [ -n "$vol" ] || return 1
  kubectl get pv "$vol" -o jsonpath='{.spec.local.path}' 2>/dev/null
}

backup_databases() {
  local backup_dir="${BACKUP_ROOT}/${TIMESTAMP}"
  mkdir -p "$backup_dir"

  for svc in "${!SERVICES[@]}"; do
    IFS='|' read -r deploy db secret <<< "${SERVICES[$svc]}"
    local pass dump_file
    pass=$(mysql_root_pass "$secret")

    dump_file="${backup_dir}/${svc}-${db}-${TIMESTAMP}.sql"
    log "Dumping $db from $deploy..."

    kubectl -n "$NAMESPACE" exec -i "deploy/$deploy" -- \
      mysqldump -u root -p"$pass" --single-transaction --quick --routines --triggers "$db" \
      > "$dump_file"

    sha256sum "$dump_file" > "${dump_file}.sha256"

    log "Uploading $db backup to S3..."
    rclone copy --s3-no-check-bucket "$dump_file" "${RCLONE_REMOTE}:${DB_BUCKET}/databases/${TIMESTAMP}/"
    rclone copy --s3-no-check-bucket "${dump_file}.sha256" "${RCLONE_REMOTE}:${DB_BUCKET}/databases/${TIMESTAMP}/"

    rm -f "$dump_file" "${dump_file}.sha256"
    log "$db backup complete (local copy removed)."
  done
}

backup_files() {
  local wiki_uploads forum_appdata forum_wwwroot

  # Wiki uploads: additive COPY (never deletes in S3). Skip if PVC is empty —
  # old-prod still owns this data until Phase 2 migration completes.
  wiki_uploads=$(pvc_hostpath "wiki-uploads-pvc" || true)
  if [[ -n "$wiki_uploads" && -d "$wiki_uploads" ]]; then
    local n
    n=$(find "$wiki_uploads" -type f 2>/dev/null | wc -l | tr -d ' ')
    if [[ "${n:-0}" -gt 0 ]]; then
      log "Copying wiki uploads ($n files) -> ${RCLONE_REMOTE}:${UPLOADS_BUCKET}"
      rclone copy $RCLONE_OPTS "$wiki_uploads/" "${RCLONE_REMOTE}:${UPLOADS_BUCKET}"
    else
      log "Skipping wiki uploads: PVC empty (old-prod still owns this data)"
    fi
  else
    log "WARNING: wiki-uploads-pvc hostPath not found ($wiki_uploads)"
  fi

  # Forum appdata/wwwroot: additive COPY (new S3 path, keeps history)
  forum_appdata=$(pvc_hostpath "forum-appdata-pvc" || true)
  forum_wwwroot=$(pvc_hostpath "forum-wwwroot-pvc" || true)
  for p in "$forum_appdata" "$forum_wwwroot"; do
    if [[ -n "$p" && -d "$p" ]]; then
      local name
      name=$(basename "$p" | sed 's/_wetfish-prod_.*//')
      log "Copying forum files ($name) -> ${RCLONE_REMOTE}:${DB_BUCKET}/forum-files/${name}"
      rclone copy $RCLONE_OPTS "$p/" "${RCLONE_REMOTE}:${DB_BUCKET}/forum-files/${name}"
    fi
  done
}

prune_local() {
  log "Pruning local backups older than ${RETENTION_DAYS} days..."
  find "$BACKUP_ROOT" -maxdepth 1 -type d -mtime +"$RETENTION_DAYS" -exec rm -rf {} + 2>/dev/null || true
}

main() {
  require_cmds
  log "Starting k3s backup run ($TIMESTAMP)..."
  backup_databases
  backup_files
  prune_local
  log "Backup cycle complete."
}

main "$@"
