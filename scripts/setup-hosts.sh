#!/bin/bash
# Setup /etc/hosts entries for wetfish services
# This script adds necessary DNS entries to access services via ingress

set -euo pipefail

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

# Check if running as root
check_root() {
    if [[ $EUID -ne 0 ]]; then
        log_error "This script must be run with sudo privileges"
        echo "Usage: sudo $0"
        exit 1
    fi
}

# Define hosts to add
HOSTS=(
    "127.0.0.1 wiki.wetfish.local"
    "127.0.0.1 home.wetfish.local"
    "127.0.0.1 glitch.wetfish.local"
    "127.0.0.1 click.wetfish.local"
    "127.0.0.1 danger.wetfish.local"
    "127.0.0.1 grafana.wetfish.local"
    "127.0.0.1 prometheus.wetfish.local"
    "127.0.0.1 alertmanager.wetfish.local"
    "127.0.0.1 loki.wetfish.local"
    "127.0.0.1 tempo.wetfish.local"
    "127.0.0.1 traefik.wetfish.local"
)

# Marker comments for managed section
MARKER_START="# BEGIN wetfish-k8s managed hosts"
MARKER_END="# END wetfish-k8s managed hosts"

# Show what will be added
show_plan() {
    log_info "The following entries will be added to /etc/hosts:"
    echo
    echo "$MARKER_START"
    for host in "${HOSTS[@]}"; do
        echo "$host"
    done
    echo "$MARKER_END"
    echo
}

# Check if entries already exist
check_existing() {
    if grep -q "$MARKER_START" /etc/hosts; then
        log_warning "Managed entries already exist in /etc/hosts"
        return 0
    fi
    return 1
}

# Remove existing managed entries
remove_existing() {
    log_info "Removing existing managed entries..."
    if grep -q "$MARKER_START" /etc/hosts; then
        # Create a temporary file without the managed section
        sed "/$MARKER_START/,/$MARKER_END/d" /etc/hosts > /tmp/hosts.tmp
        mv /tmp/hosts.tmp /etc/hosts
        log_success "Removed existing entries"
    fi
}

# Add hosts entries
add_hosts() {
    log_info "Adding hosts entries to /etc/hosts..."

    # Backup original file
    cp /etc/hosts /etc/hosts.backup.$(date +%Y%m%d_%H%M%S)
    log_info "Created backup of /etc/hosts"

    # Add marker and hosts
    {
        echo ""
        echo "$MARKER_START"
        for host in "${HOSTS[@]}"; do
            echo "$host"
        done
        echo "$MARKER_END"
    } >> /etc/hosts

    log_success "Hosts entries added successfully"
}

# Verify entries
verify_hosts() {
    log_info "Verifying hosts entries..."

    local failed=0
    for host in "${HOSTS[@]}"; do
        local hostname=$(echo "$host" | awk '{print $2}')
        if grep -q "$hostname" /etc/hosts; then
            log_success "✓ $hostname"
        else
            log_error "✗ $hostname not found"
            failed=1
        fi
    done

    if [[ $failed -eq 0 ]]; then
        log_success "All hosts entries verified"
    else
        log_error "Some hosts entries are missing"
        return 1
    fi
}

# Show current managed entries
show_current() {
    if grep -q "$MARKER_START" /etc/hosts; then
        log_info "Current managed hosts entries:"
        sed -n "/$MARKER_START/,/$MARKER_END/p" /etc/hosts
    else
        log_info "No managed hosts entries found"
    fi
}

# Remove all managed entries
remove_all() {
    remove_existing
    log_success "All managed hosts entries removed"
}

# Show usage
show_usage() {
    echo "Usage: sudo $0 [action]"
    echo
    echo "Actions:"
    echo "  add (default)  - Add or update hosts entries"
    echo "  remove         - Remove all managed hosts entries"
    echo "  show           - Show current managed entries"
    echo "  verify         - Verify entries exist"
    echo
    echo "Examples:"
    echo "  sudo $0              # Add/update entries"
    echo "  sudo $0 remove       # Remove entries"
    echo "  sudo $0 show         # Show current entries"
}

# Main function
main() {
    local action=${1:-add}

    case "$action" in
        "add")
            check_root
            show_plan

            # Confirm with user
            read -p "Continue? (y/N) " -n 1 -r
            echo
            if [[ ! $REPLY =~ ^[Yy]$ ]]; then
                log_warning "Operation cancelled"
                exit 0
            fi

            remove_existing
            add_hosts
            verify_hosts

            echo
            log_success "Setup complete! You can now access services at:"
            for host in "${HOSTS[@]}"; do
                local hostname=$(echo "$host" | awk '{print $2}')
                echo "  http://$hostname"
            done
            ;;
        "remove")
            check_root
            remove_all
            ;;
        "show")
            show_current
            ;;
        "verify")
            verify_hosts
            ;;
        "-h"|"--help"|"help")
            show_usage
            exit 0
            ;;
        *)
            log_error "Unknown action: $action"
            show_usage
            exit 1
            ;;
    esac
}

# Run main function
main "$@"
