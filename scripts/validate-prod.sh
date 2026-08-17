#!/usr/bin/env bash
# validate-prod.sh — post-cutover validation for one service on wetfish-prod
# Runs where kubectl can reach the cluster AND public DNS resolves (or via --resolve).
#
#   validate-prod.sh <service> [host]
#
# Checks: pods ready, certificate ready, HTTPS responds 2xx/3xx.
set -uo pipefail

export KUBECONFIG="${KUBECONFIG:-/etc/rancher/k3s/k3s.yaml}"
export PATH="/usr/local/bin:/usr/bin:/bin:/opt/bin:$PATH"

SERVICE="${1:?usage: validate-prod.sh <service> [host]}"
HOST="${2:-}"
NS="${NS:-wetfish-prod}"

# default host per service
if [[ -z "$HOST" ]]; then
  case "$SERVICE" in
    home) HOST="wetfish.net" ;;
    *) HOST="$SERVICE.wetfish.net" ;;
  esac
fi

PASS=0; FAIL=0
ok()  { echo "  [OK]   $*"; PASS=$((PASS+1)); }
bad() { echo "  [FAIL] $*"; FAIL=$((FAIL+1)); }

echo "== Validating $SERVICE ($HOST) in $NS =="

# 1. Pods
pods=$(kubectl -n "$NS" get pods -l app="$SERVICE" --no-headers 2>/dev/null)
if [[ -z "$pods" ]]; then bad "no pods with app=$SERVICE"; else
  echo "$pods" | awk '{print "  pod: "$1" "$2" "$3}'
  echo "$pods" | awk '$3=="Running"{r++} END{if(r>0) print "  [OK]   pods Running"}' >/dev/null
  echo "$pods" | grep -q "Running" && ok "pods running" || bad "pods not running"
fi

# 2. Certificate
cert="${SERVICE}-tls"
st=$(kubectl -n "$NS" get certificate "$cert" -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null)
[[ "$st" == "True" ]] && ok "$cert READY" || bad "$cert not ready (${st:-no Certificate})"

# 3. HTTPS
code=$(curl -s -o /dev/null -w "%{http_code}" --connect-timeout 8 "https://$HOST/" 2>/dev/null)
case "$code" in
  2*|3*) ok "https://$HOST/ -> $code" ;;
  *) bad "https://$HOST/ -> ${code:-000}" ;;
esac

echo
echo "== $PASS ok, $FAIL fail =="
[[ $FAIL -eq 0 ]]
