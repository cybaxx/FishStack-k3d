#!/bin/bash
# Setup development k3d cluster for wetfish web-services

set -euo pipefail

# Configuration
CLUSTER_NAME="wetfish-dev"
NAMESPACE_PREFIX="wetfish"
REGISTRY_PORT="5000"
HTTP_PORT="8080"
HTTPS_PORT="8443"

# Auto-detect project directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Check prerequisites
check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check if Docker is running
    if ! docker info >/dev/null 2>&1; then
        log_error "Docker is not running. Please start Docker Desktop."
        exit 1
    fi
    
    # Check if k3d is installed
    if ! command -v k3d >/dev/null 2>&1; then
        log_error "k3d is not installed. Please run: brew install k3d"
        exit 1
    fi
    
    # Check if kubectl is installed
    if ! command -v kubectl >/dev/null 2>&1; then
        log_error "kubectl is not installed. Please run: brew install kubectl"
        exit 1
    fi

    # Check if helm is installed
    if ! command -v helm >/dev/null 2>&1; then
        log_error "helm is not installed. Please run: brew install helm"
        exit 1
    fi
    
    # Check if project directory exists
    if [[ ! -d "$PROJECT_DIR" ]]; then
        log_error "Project directory $PROJECT_DIR does not exist."
        exit 1
    fi
    
    log_success "Prerequisites check passed"
}

# Clean up existing cluster
cleanup_cluster() {
    log_info "Cleaning up existing cluster..."
    
    if k3d cluster list | grep -q "$CLUSTER_NAME"; then
        log_warning "Cluster $CLUSTER_NAME already exists. Deleting..."
        k3d cluster delete "$CLUSTER_NAME"
        log_success "Existing cluster deleted"
    fi
    
    # Clean up any existing kubeconfig contexts
    kubectl config delete-context "k3d-$CLUSTER_NAME" 2>/dev/null || true
    
    log_success "Cleanup completed"
}

# Create k3d cluster
create_cluster() {
    log_info "Creating k3d cluster: $CLUSTER_NAME"
    
    k3d cluster create "$CLUSTER_NAME" \
        --agents 2 \
        --servers 1 \
        --port "${HTTP_PORT}:80@loadbalancer" \
        --port "${HTTPS_PORT}:443@loadbalancer" \
        --volume "${PROJECT_DIR}:/src@all" \
        --registry-create "wetfish-registry:${REGISTRY_PORT}" \
        --api-port 6443 \
        --k3s-arg '--disable=traefik@server:0' \
        --kubeconfig-switch-context \
        --timeout 120s
    
    log_success "Cluster $CLUSTER_NAME created successfully"
}

# Verify cluster setup
verify_cluster() {
    log_info "Verifying cluster setup..."
    
    # Wait for nodes to be ready
    log_info "Waiting for nodes to be ready..."
    kubectl wait --for=condition=ready nodes --all --timeout=300s
    
    # Check cluster info
    kubectl cluster-info
    
    # List nodes
    log_info "Cluster nodes:"
    kubectl get nodes -o wide
    
    # Verify registry is accessible
    log_info "Verifying local registry..."
    if kubectl get pods -n k3d-wetfish-registry | grep -q registry; then
        log_success "Local registry is running"
    else
        log_error "Local registry is not running"
        return 1
    fi
}

# Setup Kubernetes namespaces
setup_namespaces() {
    log_info "Setting up Kubernetes namespaces..."
    
    # Apply namespace configuration
    if [[ -f "${PROJECT_DIR}/infrastructure/namespaces.yaml" ]]; then
        kubectl apply -f "${PROJECT_DIR}/infrastructure/namespaces.yaml"
        log_success "Namespaces created"
    else
        log_error "Namespace configuration not found at ${PROJECT_DIR}/infrastructure/namespaces.yaml"
        return 1
    fi
    
    # Verify namespaces
    log_info "Available namespaces:"
    kubectl get namespaces | grep "$NAMESPACE_PREFIX"
}

# Test cluster connectivity
test_connectivity() {
    log_info "Testing cluster connectivity..."
    
    # Test pod creation and deletion
    kubectl run test-pod --image=busybox --rm -it --restart=Never -- echo "Cluster connectivity test successful" || {
        log_error "Cluster connectivity test failed"
        return 1
    }
    
    log_success "Cluster connectivity test passed"
}

# Display access information
show_access_info() {
    log_info "Cluster access information:"
    echo
    echo "🌐 Web Access:"
    echo "  HTTP:  http://localhost:${HTTP_PORT}"
    echo "  HTTPS: https://localhost:${HTTPS_PORT}"
    echo
    echo "📦 Local Registry:"
    echo "  URL:   localhost:${REGISTRY_PORT}"
    echo "  Usage: docker tag app:latest localhost:${REGISTRY_PORT}/app:latest"
    echo "         docker push localhost:${REGISTRY_PORT}/app:latest"
    echo
    echo "🔧 Management Commands:"
    echo "  kubectl get nodes"
    echo "  kubectl get pods --all-namespaces"
    echo "  kubectl cluster-info"
    echo
    echo "📚 Next Steps:"
    echo "  1. Deploy Traefik: kubectl apply -f infrastructure/traefik/"
    echo "  2. Deploy services: ./scripts/deploy.sh wetfish-dev wiki"
    echo "  3. Setup monitoring: ./scripts/setup-monitoring.sh"
    echo
}

# Main function
main() {
    log_info "Setting up wetfish development Kubernetes cluster"
    echo "=================================================="
    
    check_prerequisites
    cleanup_cluster
    create_cluster
    setup_namespaces
    verify_cluster
    test_connectivity
    show_access_info
    
    log_success "🚀 wetfish development cluster is ready!"
}

# Handle script interruption
trap 'log_error "Script interrupted. Cleaning up..."; exit 1' INT TERM

# Run main function
main "$@"