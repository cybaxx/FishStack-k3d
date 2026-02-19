#!/usr/bin/env bash
set -euo pipefail

# Generate secret files for Kustomize overlays.
# Usage: ./scripts/generate-secrets.sh [--env dev|staging|prod] [--random]
#   --env ENV: Target environment (default: dev)
#   --random:  Generate random passwords instead of default dev passwords

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

USE_RANDOM=false
ENV="dev"

while [[ $# -gt 0 ]]; do
    case "$1" in
        --random) USE_RANDOM=true; shift ;;
        --env) ENV="$2"; shift 2 ;;
        *) echo "Unknown option: $1"; exit 1 ;;
    esac
done

# Validate environment
case "$ENV" in
    dev|staging|prod) ;;
    *) echo "Invalid environment: $ENV (must be dev, staging, or prod)"; exit 1 ;;
esac

# Map env to namespace
case "$ENV" in
    dev)     NAMESPACE="wetfish-dev" ;;
    staging) NAMESPACE="wetfish-staging" ;;
    prod)    NAMESPACE="wetfish-prod" ;;
esac

generate_password() {
    if $USE_RANDOM; then
        openssl rand -base64 18
    else
        echo "$1"
    fi
}

b64() {
    echo -n "$1" | base64
}

echo "Generating secret files for environment: $ENV (namespace: $NAMESPACE)..."

# Wiki MySQL secret + app secret
WIKI_ROOT_PASS=$(generate_password "wikipass")
WIKI_USER="wikiuser"
WIKI_PASS=$(generate_password "wikipass")
WIKI_DB="wikidb"
WIKI_LOGIN_PASS=$(generate_password "changeme")
WIKI_ADMIN_PASS=$(generate_password "changeme")
WIKI_BAN_PASS=$(generate_password "changeme")
WIKI_CAPTCHA=$(generate_password "changeme")

WIKI_SECRET_DIR="$PROJECT_DIR/services/wiki/k8s/overlays/$ENV"
mkdir -p "$WIKI_SECRET_DIR"
cat > "$WIKI_SECRET_DIR/secret.yaml" <<EOF
apiVersion: v1
kind: Secret
metadata:
  name: wiki-mysql-secret
  labels:
    app: wiki
    component: mysql
type: Opaque
data:
  mysql-root-password: $(b64 "$WIKI_ROOT_PASS")
  mysql-user: $(b64 "$WIKI_USER")
  mysql-password: $(b64 "$WIKI_PASS")
  mysql-database: $(b64 "$WIKI_DB")
---
apiVersion: v1
kind: Secret
metadata:
  name: wiki-app-secret
  labels:
    app: wiki
    component: web
type: Opaque
data:
  login-password: $(b64 "$WIKI_LOGIN_PASS")
  admin-password: $(b64 "$WIKI_ADMIN_PASS")
  ban-password: $(b64 "$WIKI_BAN_PASS")
  captcha-bypass: $(b64 "$WIKI_CAPTCHA")
EOF
echo "  Created services/wiki/k8s/overlays/$ENV/secret.yaml"

# Click MySQL secret
CLICK_ROOT_PASS=$(generate_password "clickpass")
CLICK_USER="clickuser"
CLICK_PASS=$(generate_password "clickpass")
CLICK_DB="clickdb"

CLICK_SECRET_DIR="$PROJECT_DIR/services/click/k8s/overlays/$ENV"
mkdir -p "$CLICK_SECRET_DIR"
cat > "$CLICK_SECRET_DIR/secret.yaml" <<EOF
apiVersion: v1
kind: Secret
metadata:
  name: click-mysql-secret
  labels:
    app: click
    component: mysql
type: Opaque
data:
  mysql-root-password: $(b64 "$CLICK_ROOT_PASS")
  mysql-user: $(b64 "$CLICK_USER")
  mysql-password: $(b64 "$CLICK_PASS")
  mysql-database: $(b64 "$CLICK_DB")
EOF
echo "  Created services/click/k8s/overlays/$ENV/secret.yaml"

# Danger MySQL secret
DANGER_ROOT_PASS=$(generate_password "dangerpass")
DANGER_USER="dangeruser"
DANGER_PASS=$(generate_password "dangerpass")
DANGER_DB="dangerdb"

DANGER_SECRET_DIR="$PROJECT_DIR/services/danger/k8s/overlays/$ENV"
mkdir -p "$DANGER_SECRET_DIR"
cat > "$DANGER_SECRET_DIR/secret.yaml" <<EOF
apiVersion: v1
kind: Secret
metadata:
  name: danger-mysql-secret
  labels:
    app: danger
    component: mysql
type: Opaque
data:
  mysql-root-password: $(b64 "$DANGER_ROOT_PASS")
  mysql-user: $(b64 "$DANGER_USER")
  mysql-password: $(b64 "$DANGER_PASS")
  mysql-database: $(b64 "$DANGER_DB")
EOF
echo "  Created services/danger/k8s/overlays/$ENV/secret.yaml"

# Add secret.yaml to kustomization resources if not already present
for svc in wiki click danger; do
    KUST_FILE="$PROJECT_DIR/services/$svc/k8s/overlays/$ENV/kustomization.yaml"
    if [[ -f "$KUST_FILE" ]] && ! grep -q 'secret.yaml' "$KUST_FILE"; then
        # Insert secret.yaml into resources list after ../../base
        if grep -q '../../base' "$KUST_FILE"; then
            awk '/\.\.\/\.\.\/base/{print; print "  - secret.yaml"; next}1' "$KUST_FILE" > "$KUST_FILE.tmp"
            mv "$KUST_FILE.tmp" "$KUST_FILE"
        elif grep -q '^resources:' "$KUST_FILE"; then
            awk '/^resources:/{print; print "  - secret.yaml"; next}1' "$KUST_FILE" > "$KUST_FILE.tmp"
            mv "$KUST_FILE.tmp" "$KUST_FILE"
        else
            printf '\nresources:\n  - secret.yaml\n' >> "$KUST_FILE"
        fi
        echo "  Added secret.yaml to $svc/$ENV kustomization.yaml"
    fi
done

echo ""
echo "Done! Secret files are gitignored and will not be committed."
if $USE_RANDOM; then
    echo "Random passwords were generated. Review the files before deploying."
else
    echo "Default dev passwords were used. Run with --random for production-like passwords."
fi
echo ""
echo "For staging/prod, consider creating secrets directly in the cluster:"
echo "  kubectl create secret generic wiki-mysql-secret --from-literal=... -n <namespace>"
