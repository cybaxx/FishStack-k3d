#!/bin/bash
# Deploy services to wetfish Kubernetes cluster
# Supports multi-environment deployment via Kustomize overlays

set -euo pipefail

# Auto-detect project directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
DEFAULT_ENV="dev"

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

# Map environment to namespace
env_to_namespace() {
    case "$1" in
        dev)        echo "wetfish-dev" ;;
        staging)    echo "wetfish-staging" ;;
        prod)       echo "wetfish-prod" ;;
        *)          echo "" ;;
    esac
}

# Show usage
show_usage() {
    echo "Usage: $0 [--env dev|staging|prod] <service> [delete]"
    echo
    echo "Options:"
    echo "  --env ENV    Target environment (default: dev)"
    echo
    echo "Examples:"
    echo "  $0 wiki                      # Deploy wiki to dev"
    echo "  $0 --env dev wiki            # Deploy wiki to dev"
    echo "  $0 --env staging wiki        # Deploy wiki to staging"
    echo "  $0 --env prod wiki           # Deploy wiki to prod"
    echo "  $0 --env dev wiki delete     # Delete wiki from dev"
    echo "  $0 monitoring                # Deploy monitoring stack"
    echo "  $0 traefik                   # Deploy Traefik"
    echo
    echo "Environments:"
    echo "  dev      - Local k3d cluster, wetfish-dev namespace"
    echo "  staging  - Staging, wetfish-staging namespace"
    echo "  prod     - Production, wetfish-prod namespace"
    echo
    echo "Available services:"
    echo "  wiki, home, glitch, click, danger"
    echo "  monitoring  - Full monitoring stack (Helm)"
    echo "  traefik     - Ingress controller (Helm)"
    echo "  cert-manager - TLS certificate manager (Helm)"
    echo
    echo "Legacy usage (backward compat):"
    echo "  $0 wetfish-dev wiki          # Same as --env dev wiki"
}

# Deploy service via Kustomize overlay
deploy_service() {
    local env=$1
    local service=$2
    local namespace
    namespace=$(env_to_namespace "$env")

    log_info "Deploying $service to $env ($namespace)..."

    local overlay_dir="${PROJECT_DIR}/services/${service}/k8s/overlays/${env}"
    if [[ ! -d "$overlay_dir" ]]; then
        log_error "Overlay not found at $overlay_dir"
        exit 1
    fi

    # Check if namespace exists
    if ! kubectl get namespace "$namespace" >/dev/null 2>&1; then
        log_error "Namespace '$namespace' does not exist. Run: kubectl apply -f infrastructure/namespaces.yaml"
        exit 1
    fi

    if ! kubectl apply -k "$overlay_dir"; then
        log_warning "Some resources failed to apply (likely missing CRDs like ServiceMonitor)"
    fi

    log_success "Service $service deployed to $env ($namespace)"

    # Show deployment status
    show_deployment_status "$namespace" "$service"
}

# Delete service
delete_service() {
    local env=$1
    local service=$2
    local namespace
    namespace=$(env_to_namespace "$env")

    log_warning "Deleting $service from $env ($namespace)..."

    local overlay_dir="${PROJECT_DIR}/services/${service}/k8s/overlays/${env}"
    if [[ -d "$overlay_dir" ]]; then
        kubectl delete -k "$overlay_dir" --ignore-not-found=true
    fi

    log_success "Service $service deleted from $env ($namespace)"
}

# Show deployment status
show_deployment_status() {
    local namespace=$1
    local service=$2

    echo
    log_info "Checking deployment status..."

    # Wait for deployment to complete (with timeout)
    if kubectl get deployment "${service}-web" -n "$namespace" >/dev/null 2>&1; then
        kubectl rollout status deployment/"${service}-web" -n "$namespace" --timeout=300s
        log_success "Deployment completed successfully"
    elif kubectl get deployment "$service" -n "$namespace" >/dev/null 2>&1; then
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

    # Deploy Promtail (log collector)
    log_info "Installing Promtail..."
    if [[ -f "${PROJECT_DIR}/monitoring/values/promtail-values.yaml" ]]; then
        helm upgrade --install promtail grafana/promtail \
            --namespace wetfish-monitoring \
            --values "${PROJECT_DIR}/monitoring/values/promtail-values.yaml" \
            --wait --timeout 5m
    else
        log_warning "Promtail values file not found, using defaults"
        helm upgrade --install promtail grafana/promtail \
            --namespace wetfish-monitoring \
            --wait --timeout 5m
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

# Deploy cert-manager
deploy_cert_manager() {
    log_info "Deploying cert-manager..."

    helm repo add jetstack https://charts.jetstack.io
    helm repo update

    helm upgrade --install cert-manager jetstack/cert-manager \
        --namespace cert-manager \
        --create-namespace \
        --set crds.enabled=true \
        --wait --timeout 5m

    log_info "Applying ClusterIssuer..."
    kubectl apply -f "${PROJECT_DIR}/infrastructure/cert-manager/cluster-issuer.yaml"

    log_success "cert-manager deployed with self-signed ClusterIssuer"
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
    local env=$1
    local service=$2
    local namespace
    namespace=$(env_to_namespace "$env")

    echo
    log_info "Access Information:"

    # Get ingress URLs
    local ingress_host
    ingress_host=$(kubectl get ingress "$service-ingress" -n "$namespace" -o jsonpath='{.spec.rules[0].host}' 2>/dev/null || echo "")
    if [[ -n "$ingress_host" ]]; then
        echo "  Service URL: http://$ingress_host"
        if [[ "$env" == "dev" ]]; then
            echo "  Add to /etc/hosts: 127.0.0.1 $ingress_host"
        fi
    fi

    # Show port-forwarding info
    echo "  Port forwarding:"
    echo "    kubectl port-forward svc/${service}-web 8080:80 -n $namespace"

    # Show logs command
    echo "  View logs:"
    echo "    kubectl logs deployment/${service}-web -n $namespace -f"
}

# Main function
main() {
    local env="$DEFAULT_ENV"
    local service=""
    local action="deploy"

    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --env)
                env="$2"
                shift 2
                ;;
            -h|--help|help)
                show_usage
                exit 0
                ;;
            *)
                if [[ -z "$service" ]]; then
                    # Backward compat: if first arg looks like a namespace, map to env
                    case "$1" in
                        wetfish-dev)
                            env="dev"
                            ;;
                        wetfish-staging)
                            env="staging"
                            ;;
                        wetfish-prod)
                            env="prod"
                            ;;
                        wetfish-monitoring|wetfish-system)
                            # Legacy usage: $0 wetfish-monitoring monitoring
                            # Just skip the namespace arg, next arg is the service
                            shift
                            continue
                            ;;
                        *)
                            service="$1"
                            ;;
                    esac
                elif [[ "$service" == "" ]]; then
                    service="$1"
                else
                    action="$1"
                fi
                shift
                ;;
        esac
    done

    # Validate environment
    if [[ -z "$(env_to_namespace "$env")" ]]; then
        log_error "Invalid environment: $env (must be dev, staging, or prod)"
        exit 1
    fi

    case "$service" in
        "monitoring")
            deploy_monitoring
            ;;
        "cert-manager")
            deploy_cert_manager
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
            # Validate service directory exists
            local service_dir="${PROJECT_DIR}/services/${service}"
            if [[ ! -d "$service_dir" ]]; then
                log_error "Service directory '$service_dir' does not exist"
                exit 1
            fi

            case "$action" in
                "delete")
                    delete_service "$env" "$service"
                    ;;
                *)
                    deploy_service "$env" "$service"
                    show_access_info "$env" "$service"
                    ;;
            esac
            ;;
    esac
}

# Run main function
main "$@"
