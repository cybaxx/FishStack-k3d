#!/bin/bash
# Test deployment health and connectivity
# Verifies pods, services, ingresses, and basic HTTP connectivity

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
    echo "Usage: $0 [namespace] [service]"
    echo
    echo "Examples:"
    echo "  $0                      # Test all services in default namespace"
    echo "  $0 wetfish-dev          # Test all services in wetfish-dev"
    echo "  $0 wetfish-dev wiki     # Test wiki service only"
    echo
}

# Check pod health
check_pods() {
    local namespace=$1
    local service=${2:-}

    log_info "Checking pod health in namespace: $namespace"

    local selector=""
    if [[ -n "$service" ]]; then
        selector="-l app=$service"
    fi

    local pods=$(kubectl get pods -n "$namespace" $selector --no-headers 2>/dev/null || echo "")

    if [[ -z "$pods" ]]; then
        log_warning "No pods found in namespace $namespace"
        return 1
    fi

    local failed=0
    while IFS= read -r line; do
        local pod_name=$(echo "$line" | awk '{print $1}')
        local ready=$(echo "$line" | awk '{print $2}')
        local status=$(echo "$line" | awk '{print $3}')
        local restarts=$(echo "$line" | awk '{print $4}')

        if [[ "$status" == "Running" ]] && [[ "$ready" == *"/"* ]]; then
            local ready_count=$(echo "$ready" | cut -d'/' -f1)
            local total_count=$(echo "$ready" | cut -d'/' -f2)

            if [[ "$ready_count" == "$total_count" ]]; then
                log_success "✓ $pod_name ($ready) - $status"
            else
                log_error "✗ $pod_name ($ready) - Not all containers ready"
                failed=1
            fi

            # Warn if high restart count
            if [[ $restarts -gt 5 ]]; then
                log_warning "  High restart count: $restarts"
            fi
        else
            log_error "✗ $pod_name - $status"
            failed=1
        fi
    done <<< "$pods"

    return $failed
}

# Check service availability
check_services() {
    local namespace=$1
    local service=${2:-}

    log_info "Checking services in namespace: $namespace"

    local selector=""
    if [[ -n "$service" ]]; then
        selector="-l app=$service"
    fi

    local services=$(kubectl get svc -n "$namespace" $selector --no-headers 2>/dev/null || echo "")

    if [[ -z "$services" ]]; then
        log_warning "No services found in namespace $namespace"
        return 1
    fi

    local failed=0
    while IFS= read -r line; do
        local svc_name=$(echo "$line" | awk '{print $1}')
        local svc_type=$(echo "$line" | awk '{print $2}')
        local cluster_ip=$(echo "$line" | awk '{print $3}')
        local ports=$(echo "$line" | awk '{print $5}')

        if [[ "$cluster_ip" != "None" ]] && [[ "$cluster_ip" != "<none>" ]]; then
            log_success "✓ $svc_name ($svc_type) - $cluster_ip:$ports"
        else
            log_warning "⚠ $svc_name ($svc_type) - No ClusterIP"
        fi
    done <<< "$services"

    return $failed
}

# Check ingress configuration
check_ingress() {
    local namespace=$1
    local service=${2:-}

    log_info "Checking ingress rules in namespace: $namespace"

    local selector=""
    if [[ -n "$service" ]]; then
        selector="-l app=$service"
    fi

    local ingresses=$(kubectl get ingress -n "$namespace" $selector --no-headers 2>/dev/null || echo "")

    if [[ -z "$ingresses" ]]; then
        log_warning "No ingress rules found in namespace $namespace"
        return 1
    fi

    local failed=0
    while IFS= read -r line; do
        local ing_name=$(echo "$line" | awk '{print $1}')
        local hosts=$(echo "$line" | awk '{print $3}')
        local address=$(echo "$line" | awk '{print $4}')

        if [[ -n "$hosts" ]] && [[ "$hosts" != "*" ]]; then
            log_success "✓ $ing_name - $hosts"

            # Check if host is in /etc/hosts
            if grep -q "$hosts" /etc/hosts 2>/dev/null; then
                log_success "  Host $hosts found in /etc/hosts"
            else
                log_warning "  Host $hosts NOT in /etc/hosts - run: sudo ./scripts/setup-hosts.sh"
            fi
        else
            log_warning "⚠ $ing_name - No hosts configured"
        fi
    done <<< "$ingresses"

    return $failed
}

# Test HTTP connectivity
test_http_connectivity() {
    local namespace=$1
    local service=${2:-}

    log_info "Testing HTTP connectivity..."

    local selector=""
    if [[ -n "$service" ]]; then
        selector="-l app=$service"
    fi

    local ingresses=$(kubectl get ingress -n "$namespace" $selector -o jsonpath='{range .items[*]}{.spec.rules[*].host}{"\n"}{end}' 2>/dev/null || echo "")

    if [[ -z "$ingresses" ]]; then
        log_warning "No ingress hosts to test"
        return 1
    fi

    local failed=0
    while IFS= read -r host; do
        if [[ -n "$host" ]]; then
            log_info "Testing http://$host ..."

            # Test with curl (timeout 5 seconds)
            if curl -s -o /dev/null -w "%{http_code}" --connect-timeout 5 "http://$host" | grep -q "^[23]"; then
                log_success "✓ http://$host is accessible"
            else
                local status_code=$(curl -s -o /dev/null -w "%{http_code}" --connect-timeout 5 "http://$host" 2>/dev/null || echo "000")
                if [[ "$status_code" == "000" ]]; then
                    log_error "✗ http://$host is not accessible (connection failed)"
                else
                    log_warning "⚠ http://$host returned status code: $status_code"
                fi
                failed=1
            fi
        fi
    done <<< "$ingresses"

    return $failed
}

# Check logs for errors
check_logs() {
    local namespace=$1
    local service=${2:-}

    log_info "Checking recent logs for errors..."

    local selector=""
    if [[ -n "$service" ]]; then
        selector="-l app=$service"
    fi

    local pods=$(kubectl get pods -n "$namespace" $selector -o name 2>/dev/null || echo "")

    if [[ -z "$pods" ]]; then
        log_warning "No pods found to check logs"
        return 1
    fi

    local found_errors=0
    while IFS= read -r pod; do
        local pod_name=$(basename "$pod")
        log_info "Checking logs for $pod_name..."

        # Get last 50 lines and look for error keywords
        local error_count=$(kubectl logs "$pod" -n "$namespace" --tail=50 2>/dev/null | \
            grep -iE "(error|fatal|exception|failed)" | wc -l | tr -d ' ')

        if [[ $error_count -gt 0 ]]; then
            log_warning "  Found $error_count potential errors in logs"
            found_errors=1
        else
            log_success "  No obvious errors in recent logs"
        fi
    done <<< "$pods"

    return $found_errors
}

# Run all tests
run_all_tests() {
    local namespace=${1:-$DEFAULT_NAMESPACE}
    local service=${2:-}

    echo "=========================================="
    log_info "Testing deployment in namespace: $namespace"
    if [[ -n "$service" ]]; then
        log_info "Service filter: $service"
    fi
    echo "=========================================="
    echo

    local total_failures=0

    # Test 1: Pod health
    echo "TEST 1: Pod Health"
    echo "-------------------"
    if check_pods "$namespace" "$service"; then
        log_success "Pod health check passed"
    else
        log_error "Pod health check failed"
        ((total_failures++))
    fi
    echo

    # Test 2: Services
    echo "TEST 2: Services"
    echo "-------------------"
    if check_services "$namespace" "$service"; then
        log_success "Service check passed"
    else
        log_error "Service check failed"
        ((total_failures++))
    fi
    echo

    # Test 3: Ingress
    echo "TEST 3: Ingress Configuration"
    echo "-------------------"
    if check_ingress "$namespace" "$service"; then
        log_success "Ingress check passed"
    else
        log_warning "Ingress check had warnings"
    fi
    echo

    # Test 4: HTTP Connectivity
    echo "TEST 4: HTTP Connectivity"
    echo "-------------------"
    if test_http_connectivity "$namespace" "$service"; then
        log_success "HTTP connectivity check passed"
    else
        log_error "HTTP connectivity check failed"
        ((total_failures++))
    fi
    echo

    # Test 5: Recent logs
    echo "TEST 5: Recent Logs"
    echo "-------------------"
    if check_logs "$namespace" "$service"; then
        log_success "Log check passed"
    else
        log_warning "Log check found potential issues"
    fi
    echo

    # Summary
    echo "=========================================="
    if [[ $total_failures -eq 0 ]]; then
        log_success "🎉 All tests passed!"
    else
        log_error "⚠️  $total_failures test(s) failed"
        return 1
    fi
    echo "=========================================="
}

# Main function
main() {
    local namespace=${1:-$DEFAULT_NAMESPACE}
    local service=${2:-}

    if [[ "$namespace" == "-h" ]] || [[ "$namespace" == "--help" ]]; then
        show_usage
        exit 0
    fi

    # Check if namespace exists
    if ! kubectl get namespace "$namespace" >/dev/null 2>&1; then
        log_error "Namespace '$namespace' does not exist"
        exit 1
    fi

    run_all_tests "$namespace" "$service"
}

# Run main function
main "$@"
