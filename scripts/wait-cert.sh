#!/usr/bin/env bash
# wait-cert.sh — poll a cert-manager Certificate until it is READY (or timeout)
# Runs where kubectl can reach the cluster.
set -uo pipefail

export KUBECONFIG="${KUBECONFIG:-/etc/rancher/k3s/k3s.yaml}"
export PATH="/usr/local/bin:/usr/bin:/bin:/opt/bin:$PATH"

CERT="${1:?usage: wait-cert.sh <certificate-name> [timeout-seconds]}"
TIMEOUT="${2:-300}"
NS="${NS:-wetfish-prod}"
INTERVAL=10
elapsed=0

while (( elapsed < TIMEOUT )); do
  st=$(kubectl -n "$NS" get certificate "$CERT" -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null)
  reason=$(kubectl -n "$NS" get certificate "$CERT" -o jsonpath='{.status.conditions[?(@.type=="Ready")].reason}' 2>/dev/null)
  case "$st" in
    True) echo "certificate $CERT is READY"; exit 0 ;;
    False) echo "certificate $CERT failed: ${reason:-unknown}"; exit 1 ;;
  esac
  echo "[$elapsed/${TIMEOUT}s] $CERT not ready yet (${st:-no status}, ${reason:-waiting})..."
  sleep "$INTERVAL"
  elapsed=$((elapsed + INTERVAL))
done

echo "TIMEOUT: certificate $CERT not ready after ${TIMEOUT}s"
exit 1
