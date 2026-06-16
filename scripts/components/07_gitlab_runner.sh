#!/bin/bash
# Deploys the GitLab Runner pod to the k3s cluster.
# Registration against GitLab is a manual step performed after GitLab is up:
#
#   kubectl exec -n ci deploy/gitlab-runner -- gitlab-runner register \
#     --non-interactive \
#     --url http://gitlab.homelab.local \
#     --registration-token <TOKEN> \
#     --executor docker \
#     --docker-image alpine:latest \
#     --description "pi-k3s-runner" \
#     --tag-list "pi,docker,homelab"
#
# Token: GitLab → Admin Area → CI/CD → Runners → Register an instance runner.
#
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../lib/common.sh"
source "$SCRIPT_DIR/../config.sh"

KUBECONFIG="${KUBECONFIG_PATH}" export KUBECONFIG

PROJECT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"

log_info "Applying GitLab Runner manifests (namespace: ci)..."
kubectl apply -f "$PROJECT_DIR/deployments/ci/gitlab-runner/pvc.yaml"
kubectl apply -f "$PROJECT_DIR/deployments/ci/gitlab-runner/deployment.yaml"

log_info "Waiting for gitlab-runner pod to be ready..."
kubectl rollout status deployment/gitlab-runner -n ci --timeout=120s

log_info "GitLab Runner deployed. Register it after GitLab is up:"
log_info "  kubectl exec -n ci deploy/gitlab-runner -- gitlab-runner register \\"
log_info "    --non-interactive \\"
log_info "    --url http://gitlab.homelab.local \\"
log_info "    --registration-token <TOKEN> \\"
log_info "    --executor docker --docker-image alpine:latest \\"
log_info "    --description pi-k3s-runner --tag-list pi,docker,homelab"
