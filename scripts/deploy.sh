#!/bin/bash
# Deploy services to wetfish Kubernetes cluster

set -euo pipefail

# Auto-detect project directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
DEFAULT_NAMESPACE="wetfish-dev"

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

# Show usage
show_usage() {
    echo "Usage: $0 [namespace] [service] [action]"
    echo
    echo "Examples:"
    echo "  $0 wetfish-dev wiki     # Deploy wiki service to dev"
    echo "  $0 wetfish-dev wiki delete   # Delete wiki service from dev"
    echo "  $0 wetfish-monitoring monitoring  # Deploy monitoring stack"
    echo
    echo "Available services:"
    echo "  wiki           - MediaWiki application"
    echo "  monitoring      - Full monitoring stack"
    echo "  traefik        - Ingress controller"
    echo
    echo "Available namespaces:"
    echo "  wetfish-dev       - Development environment"
    echo "  wetfish-monitoring - Monitoring stack"
    echo "  wetfish-system    - Infrastructure"
}

# Validate namespace and service
validate_inputs() {
    local namespace=${1:-$DEFAULT_NAMESPACE}
    local service=${2:-}
    local action=${3:-deploy}
    
    if [[ -z "$service" ]]; then
        log_error "Service name is required"
        show_usage
        exit 1
    fi
    
    # Check if namespace exists
    if ! kubectl get namespace "$namespace" >/dev/null 2>&1; then
        log_error "Namespace '$namespace' does not exist"
        exit 1
    fi
    
    # Check if service directory exists
    local service_dir="${PROJECT_DIR}/services/${service}"
    if [[ ! -d "$service_dir" ]]; then
        log_error "Service directory '$service_dir' does not exist"
        exit 1
    fi
    
    echo "Namespace: $namespace"
    echo "Service: $service"
    echo "Action: $action"
}

# Deploy service
deploy_service() {
    local namespace=$1
    local service=$2
    
    log_info "Deploying $service to namespace $namespace..."
    
    local k8s_dir="${PROJECT_DIR}/services/${service}/k8s"
    if [[ ! -d "$k8s_dir" ]]; then
        log_error "Kubernetes manifests not found at $k8s_dir"
        exit 1
    fi

    # Apply all YAML files in order
    for manifest in "$k8s_dir"/*.yaml; do
        if [[ -f "$manifest" ]]; then
            log_info "Applying $(basename "$manifest")"
            if ! kubectl apply -f "$manifest" -n "$namespace" 2>/dev/null; then
                log_warning "Skipped $(basename "$manifest") (may require CRDs not yet installed)"
            fi
        fi
    done

    log_success "Service $service deployed to $namespace"

    # Show deployment status
    show_deployment_status "$namespace" "$service"
}

# Delete service
delete_service() {
    local namespace=$1
    local service=$2
    
    log_warning "Deleting $service from namespace $namespace..."
    
    local k8s_dir="${PROJECT_DIR}/services/${service}/k8s"
    if [[ -d "$k8s_dir" ]]; then
        # Delete all YAML files
        for manifest in "$k8s_dir"/*.yaml; do
            if [[ -f "$manifest" ]]; then
                log_info "Deleting $(basename "$manifest")"
                kubectl delete -f "$manifest" -n "$namespace" --ignore-not-found=true
            fi
        done
    fi
    
    log_success "Service $service deleted from $namespace"
}

# Show deployment status
show_deployment_status() {
    local namespace=$1
    local service=$2
    
    echo
    log_info "Checking deployment status..."
    
    # Wait for deployment to complete (with timeout)
    if kubectl get deployment "$service" -n "$namespace" >/dev/null 2>&1; then
        kubectl rollout status deployment/"$service" -n "$namespace" --timeout=300s
        log_success "Deployment completed successfully"
    else
        log_warning "No deployment found for $service"
    fi
    
    # Show pod status
    echo
    log_info "Pod status:"
    kubectl get pods -n "$namespace" -l app="$service" --show-labels
    
    # Show service status
    echo
    log_info "Service status:"
    kubectl get services -n "$namespace" -l app="$service"
    
    # Show ingress status
    echo
    log_info "Ingress status:"
    kubectl get ingress -n "$namespace" -l app="$service"
}

# Deploy monitoring stack
deploy_monitoring() {
    log_info "Deploying monitoring stack..."

    # Add Helm repositories
    log_info "Adding Helm repositories..."
    helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
    helm repo add grafana https://grafana.github.io/helm-charts
    helm repo update

    # Deploy Prometheus stack
    log_info "Installing Prometheus stack..."
    if [[ -f "${PROJECT_DIR}/monitoring/values/prometheus-stack-values.yaml" ]]; then
        helm upgrade --install prometheus prometheus-community/kube-prometheus-stack \
            --namespace wetfish-monitoring \
            --create-namespace \
            --values "${PROJECT_DIR}/monitoring/values/prometheus-stack-values.yaml" \
            --wait --timeout 10m
    else
        log_warning "Prometheus values file not found, using defaults"
        helm upgrade --install prometheus prometheus-community/kube-prometheus-stack \
            --namespace wetfish-monitoring \
            --create-namespace \
            --wait --timeout 10m
    fi

    # Deploy Loki
    log_info "Installing Loki..."
    if [[ -f "${PROJECT_DIR}/monitoring/values/loki-values.yaml" ]]; then
        helm upgrade --install loki grafana/loki \
            --namespace wetfish-monitoring \
            --values "${PROJECT_DIR}/monitoring/values/loki-values.yaml" \
            --wait --timeout 10m
    else
        log_warning "Loki values file not found, using defaults"
        helm upgrade --install loki grafana/loki \
            --namespace wetfish-monitoring \
            --wait --timeout 10m
    fi

    # Deploy Tempo
    log_info "Installing Tempo..."
    if [[ -f "${PROJECT_DIR}/monitoring/values/tempo-values.yaml" ]]; then
        helm upgrade --install tempo grafana/tempo \
            --namespace wetfish-monitoring \
            --values "${PROJECT_DIR}/monitoring/values/tempo-values.yaml" \
            --wait --timeout 10m
    else
        log_warning "Tempo values file not found, using defaults"
        helm upgrade --install tempo grafana/tempo \
            --namespace wetfish-monitoring \
            --wait --timeout 10m
    fi

    log_success "Monitoring stack deployed"

    # Show access info
    echo
    log_info "Monitoring Access URLs (add to /etc/hosts):"
    echo "  Grafana:       http://grafana.wetfish.local"
    echo "  Prometheus:    http://prometheus.wetfish.local"
    echo "  Alertmanager:  http://alertmanager.wetfish.local"
    echo "  Loki:          http://loki.wetfish.local"
    echo "  Tempo:         http://tempo.wetfish.local"
    echo
    log_info "Grafana default credentials: admin / admin"
}

# Deploy Traefik
deploy_traefik() {
    log_info "Deploying Traefik ingress controller..."
    
    # Add Traefik Helm repository
    helm repo add traefik https://helm.traefik.io/traefik
    helm repo update
    
    # Install Traefik
    helm install traefik traefik/traefik \
        --namespace wetfish-system \
        --create-namespace \
        --set ports.web redirectTo=websecure \
        --set ports.websecure.tls.options=default \
        --set service.type=LoadBalancer \
        --set service.nodePorts.http=30080 \
        --set service.nodePorts.https=30443 \
        --set providers.kubernetesCRD.enabled=true \
        --wait
    
    log_success "Traefik ingress controller deployed"
}

# Show access information
show_access_info() {
    local namespace=$1
    local service=$2
    
    echo
    log_info "Access Information:"
    
    # Get ingress URLs
    local ingress_host=$(kubectl get ingress "$service-ingress" -n "$namespace" -o jsonpath='{.spec.rules[0].host}' 2>/dev/null || echo "")
    if [[ -n "$ingress_host" ]]; then
        echo "🌐 Service URL: http://$ingress_host"
        echo "   Add to /etc/hosts: 127.0.0.1 $ingress_host"
    fi
    
    # Show port-forwarding info
    echo "🔧 Port forwarding:"
    echo "   kubectl port-forward svc/$service 8080:80 -n $namespace"
    
    # Show logs command
    echo "📋 View logs:"
    echo "   kubectl logs deployment/$service -n $namespace -f"
}

# Main function
main() {
    local namespace=${1:-$DEFAULT_NAMESPACE}
    local service=${2:-}
    local action=${3:-deploy}
    
    case "$service" in
        "help"|"-h"|"--help")
            show_usage
            exit 0
            ;;
        "monitoring")
            deploy_monitoring
            ;;
        "traefik")
            deploy_traefik
            ;;
        "")
            log_error "Service name is required"
            show_usage
            exit 1
            ;;
        *)
            validate_inputs "$namespace" "$service" "$action"
            
            case "$action" in
                "delete")
                    delete_service "$namespace" "$service"
                    ;;
                *)
                    deploy_service "$namespace" "$service"
                    show_access_info "$namespace" "$service"
                    ;;
            esac
            ;;
    esac
}

# Run main function
main "$@"