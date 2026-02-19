#!/bin/bash
set -euo pipefail

# Bootstrap FluxCD on a staging or production cluster
# Prerequisites: flux CLI, kubectl configured for target cluster, GITHUB_TOKEN env var

ENV=${1:?"Usage: $0 <staging|prod> [--age-key <path-to-age-key>]"}
AGE_KEY=""

shift
while [[ $# -gt 0 ]]; do
    case $1 in
        --age-key)
            AGE_KEY="$2"
            shift 2
            ;;
        *)
            echo "Unknown option: $1"
            exit 1
            ;;
    esac
done

if [[ "$ENV" != "staging" && "$ENV" != "prod" ]]; then
    echo "Error: Environment must be 'staging' or 'prod'"
    exit 1
fi

echo "==> Checking prerequisites..."
command -v flux >/dev/null 2>&1 || { echo "Error: flux CLI not found. Install with: brew install fluxcd/tap/flux"; exit 1; }
command -v kubectl >/dev/null 2>&1 || { echo "Error: kubectl not found"; exit 1; }

echo "==> Running Flux pre-flight checks..."
flux check --pre

echo "==> Bootstrapping Flux for ${ENV}..."
flux bootstrap github \
    --owner=cybaxx \
    --repository=web-services-k8s \
    --path=clusters/${ENV} \
    --branch=main \
    --personal

# Deploy SOPS age key if provided
if [[ -n "$AGE_KEY" ]]; then
    echo "==> Deploying SOPS age key to flux-system namespace..."
    kubectl create secret generic sops-age \
        --namespace=flux-system \
        --from-file=age.agekey="${AGE_KEY}" \
        --dry-run=client -o yaml | kubectl apply -f -
    echo "==> SOPS age key deployed"
fi

echo "==> Flux bootstrap complete for ${ENV}"
echo ""
echo "Useful commands:"
echo "  flux get kustomizations -A      # Check Kustomization status"
echo "  flux get helmreleases -A        # Check HelmRelease status"
echo "  flux get images all -A          # Check image automation status"
echo "  flux reconcile source git flux-system  # Force git pull"
echo "  flux logs --level=error         # View error logs"
