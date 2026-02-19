#!/usr/bin/env bash
# Setup development k3d cluster for wetfish web-services

set -euo pipefail

#######################################
# Configuration
#######################################
CLUSTER_NAME="wetfish-dev"
NAMESPACE_PREFIX="wetfish"
REGISTRY_NAME="wetfish-registry"
REGISTRY_PORT="5000"
HTTP_PORT="8080"
HTTPS_PORT="8443"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

#######################################
# Colors
#######################################
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

#######################################
# Logging
#######################################
log_info()    { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
log_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
log_error()   { echo -e "${RED}[ERROR]${NC} $1"; }

#######################################
# Prerequisites
#######################################
check_prerequisites() {
    log_info "Checking prerequisites..."

    command -v docker  >/dev/null || { log_error "Docker not installed"; exit 1; }
    command -v k3d     >/dev/null || { log_error "k3d not installed"; exit 1; }
    command -v kubectl >/dev/null || { log_error "kubectl not installed"; exit 1; }
    command -v helm    >/dev/null || { log_error "helm not installed"; exit 1; }

    docker info >/dev/null 2>&1 || { log_error "Docker daemon not running"; exit 1; }

    [[ -d "$PROJECT_DIR" ]] || { log_error "Project directory missing"; exit 1; }

    log_success "Prerequisites check passed"
}

#######################################
# Git submodules
#######################################
init_submodules() {
    log_info "Initializing git submodules..."
    cd "$PROJECT_DIR"
    git submodule update --init --recursive
    log_success "Git submodules initialized"
}

#######################################
# Cleanup existing cluster
#######################################
cleanup_cluster() {
    log_info "Cleaning up existing cluster..."

    if k3d cluster list | grep -q "$CLUSTER_NAME"; then
        log_warning "Deleting existing cluster..."
        k3d cluster delete "$CLUSTER_NAME"
    fi

    kubectl config delete-context "k3d-$CLUSTER_NAME" 2>/dev/null || true

    log_success "Cleanup completed"
}

#######################################
# Create cluster
#######################################
create_cluster() {
    log_info "Creating k3d cluster: $CLUSTER_NAME"

    k3d cluster create "$CLUSTER_NAME" \
        --agents 2 \
        --servers 1 \
        --port "${HTTP_PORT}:80@loadbalancer" \
        --port "${HTTPS_PORT}:443@loadbalancer" \
        --volume "${PROJECT_DIR}:/src@all" \
        --registry-create "${REGISTRY_NAME}:${REGISTRY_PORT}" \
        --api-port 6443 \
        --k3s-arg '--disable=traefik@server:0' \
        --kubeconfig-switch-context \
        --timeout 120s

    log_success "Cluster created"

    # containerd sometimes needs a moment to receive registry mirror config
    log_info "Waiting for container runtime initialization..."
    sleep 5
}

#######################################
# Registry verification (CORRECT LAYER)
#######################################
verify_registry() {
    log_info "Verifying local registry..."

    if ! docker ps --format '{{.Names}}' | grep -q "^${REGISTRY_NAME}$"; then
        log_error "Registry container not running"
        return 1
    fi

    if ! curl -fs "http://localhost:${REGISTRY_PORT}/v2/_catalog" >/dev/null 2>&1; then
        log_error "Registry API not responding"
        return 1
    fi

    log_success "Local registry is operational"
}

#######################################
# Verify cluster
#######################################
verify_cluster() {
    log_info "Verifying cluster setup..."

    log_info "Waiting for nodes to become ready..."
    kubectl wait --for=condition=ready nodes --all --timeout=300s

    kubectl cluster-info

    log_info "Cluster nodes:"
    kubectl get nodes -o wide

    verify_registry
}

#######################################
# Namespaces
#######################################
setup_namespaces() {
    log_info "Setting up namespaces..."

    NS_FILE="${PROJECT_DIR}/infrastructure/namespaces.yaml"

    [[ -f "$NS_FILE" ]] || { log_error "Missing $NS_FILE"; return 1; }

    kubectl apply -f "$NS_FILE"

    log_info "Available namespaces:"
    kubectl get namespaces | grep "$NAMESPACE_PREFIX"

    log_success "Namespaces created"
}

#######################################
# Connectivity test
#######################################
test_connectivity() {
    log_info "Testing cluster connectivity..."

    kubectl run test-pod \
        --image=busybox \
        --rm -i --restart=Never \
        -- echo "Cluster connectivity OK" >/dev/null

    log_success "Cluster connectivity test passed"
}

#######################################
# Access info
#######################################
show_access_info() {
    echo
    log_info "Cluster access information"
    echo "----------------------------------"
    echo "HTTP  : http://localhost:${HTTP_PORT}"
    echo "HTTPS : https://localhost:${HTTPS_PORT}"
    echo
    echo "Registry: localhost:${REGISTRY_PORT}"
    echo "docker tag app:latest localhost:${REGISTRY_PORT}/app:latest"
    echo "docker push localhost:${REGISTRY_PORT}/app:latest"
    echo
    echo "kubectl get nodes"
    echo "kubectl get pods -A"
    echo
}

#######################################
# Main
#######################################
main() {
    log_info "Setting up wetfish development Kubernetes cluster"
    echo "=================================================="

    check_prerequisites
    init_submodules
    cleanup_cluster
    create_cluster
    setup_namespaces
    verify_cluster
    test_connectivity
    show_access_info

    log_success "🚀 wetfish development cluster is ready!"
}

trap 'log_error "Script interrupted"; exit 1' INT TERM

main "$@"

