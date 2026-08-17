#!/usr/bin/env bash
# snapshot-dbs.sh — one-shot named DB snapshot of ALL old-prod DBs to S3
# Runs ON old-prod (149.28.239.165). Non-destructive: uploads to a distinct
# migration-snapshots/ path and KEEPS the local dump (unlike improved-backups.sh).
#
#   snapshot-dbs.sh [label]
set -euo pipefail

SERVICE_DIR="${SERVICE_DIR:-/opt/web-services/prod/services}"
BACKUP_ROOT="${BACKUP_ROOT:-/mnt/wetfish/backups}"
RCLONE_REMOTE="${RCLONE_REMOTE:-vultr-s3}"
BUCKET="${BUCKET:-wetfish-backups}"
LABEL="${1:-migration}"

TS=$(date -u +%Y%m%d-%H%M%S)
SNAP_DIR="${BACKUP_ROOT}/${LABEL}-${TS}"
mkdir -p "$SNAP_DIR"

# service -> container suffix | db name (old-prod names)
# danger's DB is named 'fishy'; online's is 'forums'
DBS=("wiki:wiki" "online:forums" "click:click" "danger:fishy")

log() { echo "[$(date -u +%Y-%m-%dT%H:%M:%SZ)] $*"; }

for entry in "${DBS[@]}"; do
  svc="${entry%%:*}"; db="${entry##*:}"
  container="${svc}-db"
  pass=$(grep -E '^MARIADB_ROOT_PASSWORD=' "$SERVICE_DIR/$svc/mariadb.env" | cut -d= -f2- | tr -d '"')

  dump="${SNAP_DIR}/${svc}-${db}.sql"
  log "Dumping $db from $container..."
  docker exec "$container" bash -c "MYSQL_PWD='$pass' mysqldump -u root --single-transaction --quick --routines --triggers '$db'" > "$dump"
  sha256sum "$dump" > "${dump}.sha256"

  log "Uploading $db snapshot to S3..."
  rclone copy --s3-no-check-bucket "$dump" "${RCLONE_REMOTE}:${BUCKET}/migration-snapshots/${LABEL}-${TS}/"
  rclone copy --s3-no-check-bucket "${dump}.sha256" "${RCLONE_REMOTE}:${BUCKET}/migration-snapshots/${LABEL}-${TS}/"
done

log "Snapshot complete. Local copy kept at $SNAP_DIR"
log "S3 path: ${RCLONE_REMOTE}:${BUCKET}/migration-snapshots/${LABEL}-${TS}/"
