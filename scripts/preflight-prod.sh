#!/usr/bin/env bash
# preflight-prod.sh — non-destructive readiness checks for the old-prod → k3s migration
# Runs ON the k3s server (216.128.155.242). Requires SSH access to old-prod.
set -uo pipefail

export PATH="/usr/local/bin:/usr/bin:/bin:/opt/bin:$PATH"
export KUBECONFIG="${KUBECONFIG:-/etc/rancher/k3s/k3s.yaml}"

VULTR_HOST="${VULTR_HOST:-root@149.28.239.165}"
VULTR_KEY="${VULTR_KEY:-/root/.ssh/cyba_wetish}"
NAMESPACE="${NAMESPACE:-wetfish-prod}"

PASS=0; FAIL=0; WARN=0
ok()   { echo "  [OK]   $*"; PASS=$((PASS+1)); }
bad()  { echo "  [FAIL] $*"; FAIL=$((FAIL+1)); }
warn() { echo "  [WARN] $*"; WARN=$((WARN+1)); }
hdr()  { echo; echo "== $* =="; }

hdr "Cluster / namespace"
kubectl get ns "$NAMESPACE" >/dev/null 2>&1 && ok "namespace $NAMESPACE exists" || bad "namespace $NAMESPACE missing"
kubectl get nodes >/dev/null 2>&1 && ok "kubectl works" || bad "kubectl failed"

hdr "Pods (wetfish-prod)"
for d in wiki-web wiki-mysql click-web click-mysql danger-web danger-mysql forum-web forum-mysql home-web glitch-web; do
  ready=$(kubectl -n "$NAMESPACE" get deploy "$d" -o jsonpath='{.status.readyReplicas}' 2>/dev/null)
  [[ "$ready" == "1" ]] && ok "$d ready" || bad "$d not ready (readyReplicas=${ready:-none})"
done

hdr "Ingress drift (live vs git)"
# git overlays add cert-manager annotation + tls secretName for all 5 services
for svc in wiki home glitch click danger; do
  tls=$(kubectl -n "$NAMESPACE" get ingress "$svc-ingress" -o jsonpath='{.spec.tls[0].secretName}' 2>/dev/null)
  ann=$(kubectl -n "$NAMESPACE" get ingress "$svc-ingress" -o jsonpath='{.metadata.annotations.cert-manager\.io/cluster-issuer}' 2>/dev/null)
  if [[ -n "$tls" && -n "$ann" ]]; then
    ok "$svc-ingress: tls=$tls, cert-manager annotated"
  else
    warn "$svc-ingress: tls=${tls:-none}, annotation=${ann:-none} — needs overlay re-apply"
  fi
done

hdr "ClusterIssuer"
issuer=$(kubectl get clusterissuer wetfish-letsencrypt -o jsonpath='{.spec.acme.solvers[0].http01.ingress.ingressClassName}' 2>/dev/null)
dns01=$(kubectl get clusterissuer wetfish-letsencrypt -o jsonpath='{.spec.acme.solvers[0].dns01.cloudflare}' 2>/dev/null)
echo "  http01 ingressClass: ${issuer:-<none>}"
echo "  dns01 cloudflare:    ${dns01:-<none>}"
[[ -n "$issuer" ]] && ok "issuer uses http01 (matches repo)" || warn "issuer does not match repo http01 — reconcile needed"

hdr "Certificates"
for svc in wiki home glitch click danger; do
  st=$(kubectl -n "$NAMESPACE" get certificate "$svc-tls" -o jsonpath='{.status.conditions[0].status}' 2>/dev/null)
  [[ "$st" == "True" ]] && ok "$svc-tls READY" || warn "$svc-tls not ready (${st:-no Certificate object})"
done

hdr "PVC sizing vs old-prod data"
for pair in "wiki-mysql-pvc:wiki" "click-mysql-pvc:click" "danger-mysql-pvc:danger"; do
  pvc="${pair%%:*}"; svc="${pair##*:}"
  size=$(kubectl -n "$NAMESPACE" get pvc "$pvc" -o jsonpath='{.spec.resources.requests.storage}' 2>/dev/null)
  dbsize=$(ssh -i "$VULTR_KEY" -o StrictHostKeyChecking=no -o ConnectTimeout=6 "$VULTR_HOST" \
    "du -sm /opt/web-services/prod/services/$svc/db 2>/dev/null | cut -f1" 2>/dev/null)
  echo "  $pvc=$size vs $svc/db=${dbsize:-?}MiB"
  if [[ -n "$dbsize" && -n "$size" ]]; then
    pvc_mb=$(( ${size%Gi} * 1024 ))
    [[ $pvc_mb -gt $dbsize ]] && ok "$svc: PVC ${size} > data ${dbsize}MiB" || warn "$svc: data ${dbsize}MiB may exceed PVC ${size}"
  fi
done
# wiki uploads
up=$(ssh -i "$VULTR_KEY" -o StrictHostKeyChecking=no -o ConnectTimeout=6 "$VULTR_HOST" \
  "du -sm /opt/web-services/prod/services/wiki/upload 2>/dev/null | cut -f1" 2>/dev/null)
echo "  wiki uploads (old-prod) = ${up:-?}MiB vs wiki-uploads-pvc=25Gi"

hdr "Connectivity / tooling"
ssh -i "$VULTR_KEY" -o StrictHostKeyChecking=no -o ConnectTimeout=6 "$VULTR_HOST" "true" 2>/dev/null \
  && ok "SSH to old-prod works" || bad "SSH to old-prod failed"
command -v rclone >/dev/null 2>&1 && ok "rclone installed" || warn "rclone missing (needed for backups)"
rclone listremotes 2>/dev/null | grep -q "$VULTR_HOST\|vultr-s3" && ok "vultr-s3 remote present" || warn "vultr-s3 remote not configured"

hdr "Disk"
df -h / | awk 'NR==2{print "  root disk: "$5" used"}' 

echo
echo "== Summary: $PASS ok, $WARN warn, $FAIL fail =="
[[ $FAIL -eq 0 ]] || exit 1
