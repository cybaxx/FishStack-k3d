#!/bin/bash
# Bring up the entire wetfish dev stack from scratch.
# Creates cluster, builds images, generates secrets, deploys everything.
#
# Usage: ./scripts/up.sh [--skip-cluster] [--skip-build] [--skip-hosts]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

CLUSTER_NAME="wetfish-dev"
REGISTRY_PORT="5000"
REGISTRY="localhost:${REGISTRY_PORT}"

SKIP_CLUSTER=false
SKIP_BUILD=false
SKIP_HOSTS=false
WITH_MONITORING=false

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

log_info()    { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[OK]${NC} $1"; }
log_warning() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error()   { echo -e "${RED}[ERROR]${NC} $1"; }
log_step()    { echo -e "\n${CYAN}${BOLD}==> $1${NC}"; }

# Parse arguments
while [[ $# -gt 0 ]]; do
    case "$1" in
        --skip-cluster)    SKIP_CLUSTER=true; shift ;;
        --skip-build)      SKIP_BUILD=true; shift ;;
        --skip-hosts)      SKIP_HOSTS=true; shift ;;
        --with-monitoring) WITH_MONITORING=true; shift ;;
        -h|--help)
            echo "Usage: $0 [--skip-cluster] [--skip-build] [--skip-hosts] [--with-monitoring]"
            echo ""
            echo "Brings up the entire wetfish dev stack:"
            echo "  1. Creates k3d cluster (or reuses existing)"
            echo "  2. Deploys infrastructure (namespaces, Traefik, cert-manager)"
            echo "  3. Builds and pushes all service images"
            echo "  4. Generates secrets"
            echo "  5. Deploys all 5 services"
            echo "  6. (Optional) Deploys monitoring stack"
            echo "  7. Configures /etc/hosts (requires sudo)"
            echo ""
            echo "Options:"
            echo "  --skip-cluster     Reuse existing cluster, don't recreate"
            echo "  --skip-build       Skip Docker image builds (use existing images)"
            echo "  --skip-hosts       Skip /etc/hosts configuration"
            echo "  --with-monitoring  Also deploy monitoring stack (Prometheus, Grafana, Loki, Tempo)"
            exit 0
            ;;
        *) log_error "Unknown option: $1"; exit 1 ;;
    esac
done

trap 'echo ""; log_error "Script interrupted."; exit 1' INT TERM

# ─── Prerequisites ──────────────────────────────────────────────────────────

log_step "Checking prerequisites"

for cmd in docker kubectl k3d helm; do
    if command -v "$cmd" >/dev/null 2>&1; then
        log_success "$cmd found"
    else
        log_error "$cmd not found. Install with: brew install $cmd"
        exit 1
    fi
done

if ! docker info >/dev/null 2>&1; then
    log_error "Docker daemon is not running. Start Docker Desktop first."
    exit 1
fi
log_success "Docker daemon running"

# ─── Git submodules ─────────────────────────────────────────────────────────

log_step "Initializing git submodules"

cd "$PROJECT_DIR"
if git submodule status | grep -q '^-'; then
    git submodule update --init --recursive
    log_success "Submodules initialized"
else
    log_success "Submodules already initialized"
fi

# ─── Cluster ────────────────────────────────────────────────────────────────

log_step "Setting up k3d cluster"

if k3d cluster list 2>/dev/null | grep -q "$CLUSTER_NAME"; then
    if $SKIP_CLUSTER; then
        log_success "Cluster $CLUSTER_NAME exists, reusing (--skip-cluster)"
        # Make sure it's running
        if ! kubectl get nodes >/dev/null 2>&1; then
            log_info "Starting stopped cluster..."
            k3d cluster start "$CLUSTER_NAME"
        fi
    else
        log_warning "Cluster $CLUSTER_NAME exists, recreating..."
        k3d cluster delete "$CLUSTER_NAME"
        kubectl config delete-context "k3d-$CLUSTER_NAME" 2>/dev/null || true
    fi
fi

if ! k3d cluster list 2>/dev/null | grep -q "$CLUSTER_NAME"; then
    log_info "Creating cluster $CLUSTER_NAME..."
    k3d cluster create "$CLUSTER_NAME" \
        --agents 2 \
        --servers 1 \
        --port "8080:80@loadbalancer" \
        --port "8443:443@loadbalancer" \
        --volume "${PROJECT_DIR}:/src@all" \
        --registry-create "wetfish-registry:${REGISTRY_PORT}" \
        --api-port 6443 \
        --k3s-arg '--disable=traefik@server:0' \
        --kubeconfig-switch-context \
        --timeout 120s
    log_success "Cluster created"
fi

log_info "Waiting for nodes..."
kubectl wait --for=condition=ready nodes --all --timeout=300s
log_success "All nodes ready"

# ─── Infrastructure ─────────────────────────────────────────────────────────

log_step "Deploying infrastructure"

# Namespaces
log_info "Creating namespaces..."
kubectl apply -f "$PROJECT_DIR/infrastructure/namespaces.yaml"
log_success "Namespaces created"

# Traefik (raw manifests)
log_info "Deploying Traefik ingress controller..."
kubectl apply -f "$PROJECT_DIR/infrastructure/traefik/"
kubectl rollout status deployment/traefik -n wetfish-system --timeout=120s
log_success "Traefik ready"

# cert-manager + ClusterIssuer
log_info "Deploying cert-manager..."
if helm list -n cert-manager 2>/dev/null | grep -q cert-manager; then
    log_success "cert-manager already installed"
else
    helm repo add jetstack https://charts.jetstack.io --force-update >/dev/null 2>&1
    helm repo update >/dev/null 2>&1
    helm upgrade --install cert-manager jetstack/cert-manager \
        --namespace cert-manager \
        --create-namespace \
        --set crds.enabled=true \
        --wait --timeout 5m
    log_success "cert-manager installed"
fi

log_info "Applying ClusterIssuer..."
kubectl apply -f "$PROJECT_DIR/infrastructure/cert-manager/cluster-issuer.yaml"
log_success "ClusterIssuer ready"

# ─── Build images ───────────────────────────────────────────────────────────

log_step "Building and pushing container images"

build_and_push() {
    local svc=$1 dockerfile=$2 tag=$3
    local full_tag="${REGISTRY}/${svc}:${tag}"
    log_info "Building $full_tag ..."
    docker build -q -t "$full_tag" -f "$PROJECT_DIR/services/$svc/$dockerfile" "$PROJECT_DIR/services/$svc/" >/dev/null
    docker push "$full_tag" >/dev/null 2>&1
    log_success "$full_tag"
}

if $SKIP_BUILD; then
    log_warning "Skipping image builds (--skip-build)"
else
    # Build all images (parallelise where possible)
    build_and_push wiki  Dockerfile.nginx nginx  &
    build_and_push wiki  Dockerfile.php   php    &
    build_and_push home  Dockerfile       latest &
    wait
    build_and_push glitch Dockerfile.nginx nginx &
    build_and_push glitch Dockerfile.php   php   &
    build_and_push click  Dockerfile.nginx nginx &
    build_and_push click  Dockerfile.php   php   &
    wait
    build_and_push danger Dockerfile.nginx nginx &
    build_and_push danger Dockerfile.php   php   &
    wait
    log_success "All images built and pushed to local registry"
fi

# ─── Secrets ────────────────────────────────────────────────────────────────

log_step "Generating secrets"

bash "$SCRIPT_DIR/generate-secrets.sh" --env dev
log_success "Secrets generated"

# ─── Deploy services ────────────────────────────────────────────────────────

log_step "Deploying services"

SERVICES=(wiki home glitch click danger)

for svc in "${SERVICES[@]}"; do
    log_info "Deploying $svc..."
    kubectl apply -k "$PROJECT_DIR/services/$svc/k8s/overlays/dev/" 2>/dev/null || log_warning "$svc had partial apply errors (non-fatal, likely missing CRDs)"
done

log_info "Waiting for deployments to roll out..."

# Wait for all web deployments
for svc in "${SERVICES[@]}"; do
    if kubectl get deployment "${svc}-web" -n wetfish-dev >/dev/null 2>&1; then
        kubectl rollout status deployment/"${svc}-web" -n wetfish-dev --timeout=300s 2>/dev/null && \
            log_success "${svc}-web ready" || \
            log_warning "${svc}-web rollout timed out"
    elif kubectl get deployment "${svc}" -n wetfish-dev >/dev/null 2>&1; then
        kubectl rollout status deployment/"${svc}" -n wetfish-dev --timeout=300s 2>/dev/null && \
            log_success "${svc} ready" || \
            log_warning "${svc} rollout timed out"
    fi
done

# Wait for DB deployments
for svc in wiki click danger; do
    if kubectl get deployment "${svc}-mysql" -n wetfish-dev >/dev/null 2>&1; then
        kubectl rollout status deployment/"${svc}-mysql" -n wetfish-dev --timeout=300s 2>/dev/null && \
            log_success "${svc}-mysql ready" || \
            log_warning "${svc}-mysql rollout timed out"
    fi
done

# ─── Monitoring (optional) ─────────────────────────────────────────────────

if $WITH_MONITORING; then
    log_step "Deploying monitoring stack"

    log_info "Adding Helm repositories..."
    helm repo add prometheus-community https://prometheus-community.github.io/helm-charts >/dev/null 2>&1
    helm repo add grafana https://grafana.github.io/helm-charts >/dev/null 2>&1
    helm repo update >/dev/null 2>&1

    log_info "Installing kube-prometheus-stack (Prometheus + Grafana + Alertmanager)..."
    helm upgrade --install prometheus prometheus-community/kube-prometheus-stack \
        --namespace wetfish-monitoring \
        --values "$PROJECT_DIR/monitoring/values/prometheus-stack-values.yaml" \
        --wait --timeout 10m
    log_success "kube-prometheus-stack ready"

    log_info "Installing Loki..."
    helm upgrade --install loki grafana/loki \
        --namespace wetfish-monitoring \
        --values "$PROJECT_DIR/monitoring/values/loki-values.yaml" \
        --wait --timeout 10m
    log_success "Loki ready"

    log_info "Installing Tempo..."
    helm upgrade --install tempo grafana/tempo \
        --namespace wetfish-monitoring \
        --values "$PROJECT_DIR/monitoring/values/tempo-values.yaml" \
        --wait --timeout 5m
    log_success "Tempo ready"

    log_info "Installing Promtail..."
    helm upgrade --install promtail grafana/promtail \
        --namespace wetfish-monitoring \
        --values "$PROJECT_DIR/monitoring/values/promtail-values.yaml" \
        --wait --timeout 5m
    log_success "Promtail ready"

    log_success "Monitoring stack deployed"
fi

# ─── /etc/hosts ─────────────────────────────────────────────────────────────

if ! $SKIP_HOSTS; then
    log_step "Configuring /etc/hosts"

    HOSTS_NEEDED=false
    for svc in "${SERVICES[@]}"; do
        if ! grep -q "${svc}.wetfish.local" /etc/hosts 2>/dev/null; then
            HOSTS_NEEDED=true
            break
        fi
    done

    if $HOSTS_NEEDED; then
        log_warning "/etc/hosts needs updating. Running setup-hosts.sh (requires sudo)..."
        sudo bash "$SCRIPT_DIR/setup-hosts.sh" add <<< "y" || \
            log_warning "Could not update /etc/hosts. Run manually: sudo ./scripts/setup-hosts.sh"
    else
        log_success "/etc/hosts already configured"
    fi
fi

# ─── Status ─────────────────────────────────────────────────────────────────

log_step "Final status"

echo ""
kubectl get pods -n wetfish-dev -o wide
echo ""
kubectl get svc -n wetfish-dev
echo ""
kubectl get ingress -n wetfish-dev

# ─── Done ───────────────────────────────────────────────────────────────────

echo ""
echo -e "${GREEN}${BOLD}Stack is up!${NC}"
echo ""
echo "Services:"
for svc in "${SERVICES[@]}"; do
    echo "  http://${svc}.wetfish.local:8080"
done
if $WITH_MONITORING; then
    echo ""
    echo "Monitoring:"
    echo "  http://grafana.wetfish.local:8080       (admin/admin)"
    echo "  http://prometheus.wetfish.local:8080"
    echo "  http://alertmanager.wetfish.local:8080"
fi
echo ""
echo "Load DB schemas (first deploy only):"
echo "  kubectl exec -i deployment/wiki-mysql -n wetfish-dev -- mysql -uroot -pwikipass wikidb < services/wiki/src/wwwroot/src/schema.sql"
echo "  kubectl exec -i deployment/click-mysql -n wetfish-dev -- mysql -uroot -pclickpass clickdb < services/click/src/schema.sql"
echo "  kubectl exec -i deployment/danger-mysql -n wetfish-dev -- mysql -uroot -pdangerpass dangerdb < services/danger/src/schema.sql"
echo ""
echo "Teardown:"
echo "  ./scripts/cleanup.sh"
