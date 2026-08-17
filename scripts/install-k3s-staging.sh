#!/usr/bin/env bash
# install-k3s-staging.sh — install k3s on the old-prod host for the staging environment (Phase 5)
# CAUTION: run ONLY after Phase 4 decommission. Requires explicit --yes.
#
# Mirrors prod: single-node k3s with bundled traefik disabled (custom traefik is
# deployed from infrastructure/ via deploy.sh). Does NOT touch existing Docker
# data volumes (additive — containers are stopped, data is kept).
set -euo pipefail

[[ "${1:-}" == "--yes" ]] || { echo "ERROR: pass --yes to confirm you are past Phase 4 decommission."; exit 1; }

log() { echo "[$(date -u +%Y-%m-%dT%H:%M:%SZ)] $*"; }

log "Installing k3s (single node, traefik disabled)..."
curl -sfL https://get.k3s.io | sh -s - server \
  --disable=traefik \
  --write-kubeconfig-mode 644

export KUBECONFIG="${KUBECONFIG:-/etc/rancher/k3s/k3s.yaml}"
export PATH="/usr/local/bin:/usr/bin:/bin:$PATH"

log "Waiting for node ready..."
kubectl wait --for=condition=ready nodes --all --timeout=300s

log "Applying namespaces..."
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
kubectl apply -f "$PROJECT_DIR/infrastructure/namespaces.yaml"

log "Deploying traefik + cert-manager..."
"$SCRIPT_DIR/deploy.sh" traefik
"$SCRIPT_DIR/deploy.sh" cert-manager

log "k3s staging installed. Next: deploy services with ./scripts/deploy.sh --env staging <svc>"
