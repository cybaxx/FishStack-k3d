#!/bin/bash
# Clean up k3d cluster and associated resources

set -euo pipefail

# Configuration
CLUSTER_NAME="wetfish-dev"

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

# Delete k3d cluster
delete_cluster() {
    log_info "Deleting k3d cluster: $CLUSTER_NAME"
    
    if k3d cluster list | grep -q "$CLUSTER_NAME"; then
        k3d cluster delete "$CLUSTER_NAME"
        log_success "Cluster $CLUSTER_NAME deleted"
    else
        log_warning "Cluster $CLUSTER_NAME not found"
    fi
}

# Clean up kubeconfig
cleanup_kubeconfig() {
    log_info "Cleaning up kubeconfig..."
    kubectl config delete-context "k3d-$CLUSTER_NAME" 2>/dev/null || true
    log_success "Kubeconfig cleaned"
}

# Clean up Docker resources
cleanup_docker() {
    log_info "Cleaning up Docker resources..."
    
    # Remove k3d images
    docker images | grep "k3d" | awk '{print $3}' | xargs -r docker rmi 2>/dev/null || true
    
    # Clean up unused containers
    docker container prune -f
    
    # Clean up unused images
    docker image prune -f
    
    log_success "Docker resources cleaned"
}

# Clean up local hosts entries
cleanup_hosts() {
    log_info "Checking for hosts file entries..."

    if [[ -f "${PROJECT_DIR}/scripts/setup-hosts.sh" ]]; then
        log_info "To remove /etc/hosts entries, run:"
        echo "  sudo ${PROJECT_DIR}/scripts/setup-hosts.sh remove"
    else
        log_info "Note: You may need to manually remove entries from /etc/hosts:"
        echo "  127.0.0.1 wiki.wetfish.local"
        echo "  127.0.0.1 grafana.wetfish.local"
        echo "  127.0.0.1 prometheus.wetfish.local"
        echo "  (and others managed by wetfish-k8s)"
    fi
}

# Show cleanup summary
show_summary() {
    echo
    log_info "Cleanup Summary:"
    echo "✅ k3d cluster deleted"
    echo "✅ Kubeconfig cleaned"
    echo "✅ Docker resources cleaned"
    echo
    log_info "To recreate the cluster, run:"
    echo "  ./scripts/setup-dev.sh"
    echo
}

# Main function
main() {
    log_info "Starting wetfish development cluster cleanup"
    echo "=================================================="
    
    delete_cluster
    cleanup_kubeconfig
    cleanup_docker
    cleanup_hosts
    show_summary
    
    log_success "🧹 Cleanup completed successfully!"
}

# Handle script interruption
trap 'log_error "Cleanup interrupted"; exit 1' INT TERM

# Run main function
main "$@"