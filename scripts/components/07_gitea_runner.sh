#!/bin/bash
# Deploys the Gitea Runner pod to the k3s cluster.
# The runner registers automatically via GITEA_RUNNER_REGISTRATION_TOKEN.
#
# Prerequisites:
#   1. Gitea must be up and accessible at http://gitea.homelab.local
#   2. Create the runner secret with the token from Gitea → Admin → Actions → Runners:
#        kubectl create secret generic gitea-runner-secret \
#          --from-literal=GITEA_RUNNER_REGISTRATION_TOKEN=<token> -n ci
#   3. Then apply the deployment:
#        kubectl apply -f deployments/ci/gitea-runner/deployment.yaml
#
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../lib/common.sh"
source "$SCRIPT_DIR/../config.sh"

KUBECONFIG="${KUBECONFIG_PATH}" export KUBECONFIG

PROJECT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"

log_info "Creating namespace 'ci'..."
kubectl create namespace ci --dry-run=client -o yaml | kubectl apply -f -

log_info "Applying Gitea Runner PVC (namespace: ci)..."
kubectl apply -f "$PROJECT_DIR/deployments/ci/gitea-runner/pvc.yaml"

log_info "Gitea Runner PVC created. Next steps after Gitea is running:"
log_info "  1. Get token: Gitea → Site Administration → Actions → Runners"
log_info "  2. kubectl create secret generic gitea-runner-secret --from-literal=GITEA_RUNNER_REGISTRATION_TOKEN=<token> -n ci"
log_info "  3. kubectl apply -f deployments/ci/gitea-runner/deployment.yaml"
