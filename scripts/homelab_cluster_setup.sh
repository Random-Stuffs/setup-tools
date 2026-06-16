#!/bin/bash
# =============================================================================
# Homelab Cluster Setup
# Installs: k3s (containerd) | Helm | Gitea Runner | k9s
#
# Usage:
#   sudo bash homelab_cluster_setup.sh
#
# Run this AFTER homelab_essential_setup.sh and a reboot.
# =============================================================================
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/common.sh"
source "$SCRIPT_DIR/config.sh"

require_root

log_info "========================================================"
log_info " Homelab Cluster Setup"
log_info "========================================================"

log_info "--- Step 1/4: k3s (containerd runtime) ---"
bash "$SCRIPT_DIR/components/05_k3s.sh"

log_info "--- Step 2/4: Helm ---"
bash "$SCRIPT_DIR/components/06_helm.sh"

log_info "--- Step 3/4: Gitea Runner ---"
KUBECONFIG="${KUBECONFIG_PATH}" kubectl create namespace ci --dry-run=client -o yaml | KUBECONFIG="${KUBECONFIG_PATH}" kubectl apply -f -
KUBECONFIG="${KUBECONFIG_PATH}" kubectl create namespace apps --dry-run=client -o yaml | KUBECONFIG="${KUBECONFIG_PATH}" kubectl apply -f -
bash "$SCRIPT_DIR/components/07_gitea_runner.sh"

log_info "--- Step 4/4: k9s ---"
bash "$SCRIPT_DIR/components/08_k9s.sh"

log_info "========================================================"
log_info " Cluster setup complete!"
log_info "========================================================"
log_info "Cluster status:  kubectl get nodes"
log_info "Runner pods:     kubectl get pods -n ci"
log_info "TUI dashboard:   k9s"
log_info ""
log_info "Next: apply Kubernetes manifests:"
log_info "  kubectl apply -f deployments/namespaces.yaml"
log_info "  kubectl apply -f deployments/data/"
log_info "  kubectl apply -f deployments/infra/cloudflared/"
log_info "  kubectl apply -f deployments/mcp/mempalace/"
log_info "  kubectl apply -f deployments/docs/"
log_info ""
log_info "Deploy Gitea (creates secret, applies manifests, creates admin user):"
log_info "  bash scripts/deploy_gitea.sh"
log_info "========================================================"
