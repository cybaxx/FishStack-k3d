#!/bin/bash
# fix-wiki.sh — Fix Wiki dev deployment on k3d
# - Ensures PVC permissions are correct
# - Allows root access for MySQL in dev
# - Imports missing images into k3d
# - Restarts pods

set -euo pipefail

NAMESPACE="wetfish-dev"
DEPLOYMENT="wiki-mysql"
WEB_DEPLOY="wiki-web"
PVC_LIST=("wiki-mysql-pvc" "wiki-uploads-pvc" "wiki-wwwroot-pvc")
K3D_CLUSTER="k3d-wetfish-dev"
NGINX_IMAGE="wetfish-registry:5000/wiki:nginx"
PHP_IMAGE="wetfish-registry:5000/wiki:php"

log() {
    echo -e "[INFO] $1"
}

warn() {
    echo -e "\033[1;33m[WARN] $1\033[0m"
}

error() {
    echo -e "\033[0;31m[ERROR] $1\033[0m"
}

# 1️⃣ Patch deployment to allow root for dev (if needed)
log "Patching wiki-mysql deployment to allow root in dev..."
kubectl patch deployment "$DEPLOYMENT" -n "$NAMESPACE" \
  --type='json' \
  -p='[{"op": "replace", "path": "/spec/template/spec/securityContext", "value":{"runAsNonRoot":false}}]' 2>/dev/null || \
warn "Patch may already exist or failed; continuing..."

# 2️⃣ Fix PVC permissions
log "Fixing PVC permissions..."
for pvc in "${PVC_LIST[@]}"; do
    PV=$(kubectl get pvc "$pvc" -n "$NAMESPACE" -o jsonpath='{.spec.volumeName}')
    HOST_PATH=$(kubectl get pv "$PV" -o jsonpath='{.spec.local.path}')
    NODE=$(k3d node list -o json | jq -r '.[0].name')
    log "Setting ownership 1001:1001 on $HOST_PATH in node $NODE..."
    k3d node exec "$NODE" -- chown -R 1001:1001 "$HOST_PATH"
done

# 3️⃣ Ensure images exist in k3d
log "Checking images in k3d registry..."
for img in "$NGINX_IMAGE" "$PHP_IMAGE"; do
    if ! k3d image list -c "$K3D_CLUSTER" | grep -q "$(echo $img | cut -d: -f1)"; then
        log "Image $img not found locally. Pulling & importing..."
        docker pull "$img"
        k3d image import "$img" -c "$K3D_CLUSTER"
    else
        log "Image $img exists."
    fi
done

# 4️⃣ Restart pods
log "Deleting MySQL and web pods..."
kubectl delete pod -l app=wiki -n "$NAMESPACE" --ignore-not-found=true

log "✅ Dev fix applied. Watch pods with: kubectl get pods -n $NAMESPACE -w"

