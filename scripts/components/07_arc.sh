#!/bin/bash
# Installs the GitHub Actions Runner Controller (ARC) via Helm.
#
# Prerequisites:
#   - k3s running (05_k3s.sh completed)
#   - Helm installed (06_helm.sh completed)
#   - GITHUB_PAT exported in the environment:
#       export GITHUB_PAT="ghp_xxxxxxxxxxxxxxxxxxxx"
#     The PAT needs scopes: admin:org (for org-level runners) or repo (for repo-level).
#
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../lib/common.sh"
source "$SCRIPT_DIR/../config.sh"

require_root

[[ -n "${GITHUB_PAT:-}" ]] || die "GITHUB_PAT environment variable is not set. Export it before running this script."

KUBECONFIG="${KUBECONFIG_PATH}" export KUBECONFIG

log_info "Creating namespace '${GITHUB_RUNNER_NAMESPACE}'..."
kubectl create namespace "$GITHUB_RUNNER_NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -

log_info "Creating runner-secret in namespace '${GITHUB_RUNNER_NAMESPACE}'..."
kubectl create secret generic runner-secret \
    --from-literal=github_token="$GITHUB_PAT" \
    --namespace="$GITHUB_RUNNER_NAMESPACE" \
    --dry-run=client -o yaml | kubectl apply -f -

log_info "Installing ARC controller (v${ARC_CHART_VERSION})..."
helm upgrade --install arc-controller \
    oci://ghcr.io/actions/actions-runner-controller-charts/gha-runner-scale-set-controller \
    --version "$ARC_CHART_VERSION" \
    --namespace "$GITHUB_RUNNER_NAMESPACE" \
    --create-namespace \
    --wait

log_info "Installing ARC runner scale-set '${GITHUB_RUNNER_NAME}' (v${ARC_CHART_VERSION})..."
helm upgrade --install "$GITHUB_RUNNER_NAME" \
    oci://ghcr.io/actions/actions-runner-controller-charts/gha-runner-scale-set \
    --version "$ARC_CHART_VERSION" \
    --namespace "$GITHUB_RUNNER_NAMESPACE" \
    --values "$(dirname "$SCRIPT_DIR")/deployments/ci/arc/runner-values.yaml" \
    --set githubConfigUrl="$GITHUB_CONFIG_URL" \
    --set githubConfigSecret.github_token="" \
    --set existingSecret=runner-secret \
    --wait

log_info "ARC installed. Verifying pods in namespace '${GITHUB_RUNNER_NAMESPACE}'..."
kubectl get pods -n "$GITHUB_RUNNER_NAMESPACE"
