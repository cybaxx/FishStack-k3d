#!/usr/bin/env bash
# migrate-service.sh — one-shot migration of a DB-backed service: old-prod → k3s
# Runs ON the k3s server (216.128.155.242).
#
#   DB:      mysqldump (docker exec on old-prod) piped into k8s pod
#   Uploads: rsync straight into local-path PVC hostPath (wiki only)
#
# Non-destructive by default: refuses to import into a non-empty target DB
# unless --force is passed.
set -euo pipefail

export PATH="/usr/local/bin:/usr/bin:/bin:/opt/bin:$PATH"
export KUBECONFIG="${KUBECONFIG:-/etc/rancher/k3s/k3s.yaml}"

VULTR_HOST="${VULTR_HOST:-root@149.28.239.165}"
VULTR_KEY="${VULTR_KEY:-/root/.ssh/cyba_wetish}"
NAMESPACE="${NAMESPACE:-wetfish-prod}"

log() { echo "[$(date -u +%Y-%m-%dT%H:%M:%SZ)] $*"; }
die() { echo "ERROR: $*" >&2; exit 1; }

usage() {
  cat <<'EOF'
Usage: migrate-service.sh <service> [--db-only|--uploads-only] [--force]

  service: wiki | click | danger
  --force: import even if the target DB already contains tables

Runs on the k3s server. Requires SSH access to VULTR_HOST ($VULTR_HOST).
EOF
}

# service -> old-prod container | old-prod db name | k3s mysql deployment | k3s db name | k8s secret
case "${1:-}" in
  wiki)   CFG="wiki-db|wiki|wiki-mysql|wikidb|wiki-mysql-secret" ;;
  click)  CFG="click-db|click|click-mysql|clickdb|click-mysql-secret" ;;
  danger) CFG="danger-db|fishy|danger-mysql|dangerdb|danger-mysql-secret" ;;
  -h|--help|"") usage; exit 0 ;;
  *) die "unknown service '${1:-}'" ;;
esac

IFS='|' read -r OLD_CONTAINER OLD_DB K3S_DEPLOY K3S_DB K3S_SECRET <<< "$CFG"
MODE="all"
FORCE=0
for a in "${@:2}"; do
  case "$a" in
    --db-only) MODE="db" ;;
    --uploads-only) MODE="uploads" ;;
    --force) FORCE=1 ;;
    *) die "unknown flag '$a'" ;;
  esac
done

mysql_root_pass() {
  kubectl -n "$NAMESPACE" get secret "$K3S_SECRET" \
    -o jsonpath='{.data.mysql-root-password}' | base64 -d
}

old_prod_pass() {
  ssh -i "$VULTR_KEY" -o StrictHostKeyChecking=no "$VULTR_HOST" \
    "grep -E '^MARIADB_ROOT_PASSWORD=' /opt/web-services/prod/services/${1%%-db}/mariadb.env 2>/dev/null | cut -d= -f2- | tr -d '\"'"
}

pvc_hostpath() {
  local pvc=$1 vol
  vol=$(kubectl -n "$NAMESPACE" get pvc "$pvc" -o jsonpath='{.spec.volumeName}' 2>/dev/null) || return 1
  [ -n "$vol" ] || return 1
  kubectl get pv "$vol" -o jsonpath='{.spec.local.path}' 2>/dev/null
}

migrate_db() {
  local pass old_pass
  pass=$(mysql_root_pass)
  old_pass=$(old_prod_pass "$OLD_CONTAINER")

  # Safety guard: refuse to clobber an already-populated target DB
  local tables
  tables=$(kubectl -n "$NAMESPACE" exec "deploy/$K3S_DEPLOY" -- \
    mysql -u root -p"$pass" -N -e \
    "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema='$K3S_DB'" 2>/dev/null | tr -d ' ')
  if [[ "${tables:-0}" -gt 0 && "$FORCE" -ne 1 ]]; then
    die "target DB '$K3S_DB' already has $tables tables — pass --force to overwrite"
  fi

  log "Migrating $OLD_DB (old-prod) -> $K3S_DB ($K3S_DEPLOY)..."
  ssh -i "$VULTR_KEY" -o StrictHostKeyChecking=no "$VULTR_HOST" \
    "docker exec $OLD_CONTAINER mysqldump -u root -p'$old_pass' --single-transaction --quick --routines --triggers $OLD_DB" \
    | kubectl -n "$NAMESPACE" exec -i "deploy/$K3S_DEPLOY" -- \
      mysql -u root -p"$pass" "$K3S_DB"

  local after
  after=$(kubectl -n "$NAMESPACE" exec "deploy/$K3S_DEPLOY" -- \
    mysql -u root -p"$pass" -N -e \
    "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema='$K3S_DB'" 2>/dev/null | tr -d ' ')
  log "DB migration complete: $K3S_DB now has $after tables."
}

migrate_uploads() {
  [[ "$OLD_CONTAINER" == "wiki-db" ]] || die "uploads sync only applies to wiki"
  local uploads_path
  uploads_path=$(pvc_hostpath "wiki-uploads-pvc") || die "could not resolve wiki-uploads-pvc hostPath"

  log "Rsyncing wiki uploads -> $uploads_path"
  rsync -az --info=stats2 \
    -e "ssh -i $VULTR_KEY -o StrictHostKeyChecking=no" \
    "$VULTR_HOST:/mnt/wetfish/wiki/uploads/" \
    "$uploads_path/"
  log "Uploads rsync complete."
}

case "$MODE" in
  db) migrate_db ;;
  uploads) migrate_uploads ;;
  all) migrate_db; [[ "$OLD_CONTAINER" == "wiki-db" ]] && migrate_uploads ;;
esac

log "Done."
