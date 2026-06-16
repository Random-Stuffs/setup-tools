#!/bin/bash
# =============================================================================
# Gitea Deploy Script
# Deploys Gitea to the k3s cluster and creates the initial admin user.
#
# Usage (run from the project root):
#   bash scripts/deploy_gitea.sh
#
# Run this AFTER homelab_cluster_setup.sh.
# =============================================================================
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/common.sh"
source "$SCRIPT_DIR/config.sh"

PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

KUBECONFIG="${KUBECONFIG_PATH}" export KUBECONFIG

log_info "========================================================"
log_info " Gitea Deploy"
log_info "========================================================"

# --- Admin password ---
if [[ -z "${GITEA_ADMIN_PASSWORD:-}" ]]; then
    read -s -p "[INPUT] Gitea admin password: " GITEA_ADMIN_PASSWORD
    echo
fi
[[ -n "$GITEA_ADMIN_PASSWORD" ]] || die "GITEA_ADMIN_PASSWORD cannot be empty."

# --- Secret ---
log_info "Creating gitea-secret in namespace 'apps'..."
kubectl create secret generic gitea-secret \
    --from-literal=GITEA_ADMIN_PASSWORD="$GITEA_ADMIN_PASSWORD" \
    --namespace apps \
    --dry-run=client -o yaml | kubectl apply -f -

# --- Manifests ---
log_info "Applying Gitea manifests..."
kubectl apply -f "$PROJECT_DIR/deployments/apps/gitea/pvc.yaml"
kubectl apply -f "$PROJECT_DIR/deployments/apps/gitea/deployment.yaml"
kubectl apply -f "$PROJECT_DIR/deployments/apps/gitea/service.yaml"
kubectl apply -f "$PROJECT_DIR/deployments/apps/gitea/ingress.yaml"

# --- Wait ---
log_info "Waiting for Gitea to be ready (up to 2 min)..."
kubectl rollout status deployment/gitea -n apps --timeout=120s

# --- Admin user ---
log_info "Creating admin user..."
kubectl exec -n apps deploy/gitea -- \
    su git -c "gitea admin user create \
        --username admin \
        --password '${GITEA_ADMIN_PASSWORD}' \
        --email admin@gitea.homelab.local \
        --admin" 2>/dev/null \
    && log_info "Admin user created." \
    || log_info "Admin user already exists — skipping."

log_info "========================================================"
log_info " Gitea is ready!"
log_info "========================================================"
log_info "URL:      http://gitea.homelab.local"
log_info "SSH git:  ssh://git@<PI_IP>:30022"
log_info "Login:    admin / <your password>"
log_info ""
log_info "Next: register the Gitea Runner"
log_info "  1. Admin → Site Administration → Actions → Runners → copy token"
log_info "  2. kubectl create secret generic gitea-runner-secret --from-literal=GITEA_RUNNER_REGISTRATION_TOKEN=<token> -n ci"
log_info "  3. kubectl apply -f deployments/ci/gitea-runner/deployment.yaml"
log_info "========================================================"
