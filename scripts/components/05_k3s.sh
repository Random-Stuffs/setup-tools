#!/bin/bash
# Installs k3s (single-node) using the default containerd runtime.
# Copies kubeconfig to ~/.kube/config for the invoking user.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../lib/common.sh"
source "$SCRIPT_DIR/../config.sh"

require_root

REAL_USER="${SUDO_USER:-$USER}"
REAL_HOME=$(eval echo "~$REAL_USER")

if command_exists k3s; then
    log_info "k3s $(k3s --version | head -1) already installed — skipping."
else
    log_info "Installing k3s (containerd runtime)..."
    if [[ -n "$K3S_VERSION" ]]; then
        curl -sfL https://get.k3s.io | INSTALL_K3S_VERSION="$K3S_VERSION" sh -
    else
        curl -sfL https://get.k3s.io | sh -
    fi
fi

log_info "Waiting for k3s node to become Ready..."
until k3s kubectl get nodes 2>/dev/null | grep -q " Ready"; do
    sleep 3
done

log_info "Copying kubeconfig to ${KUBECONFIG_PATH}..."
mkdir -p "$(dirname "$KUBECONFIG_PATH")"
cp /etc/rancher/k3s/k3s.yaml "$KUBECONFIG_PATH"
# Fix path references inside the file (k3s uses 127.0.0.1 which is fine).
chown "$REAL_USER:$REAL_USER" "$KUBECONFIG_PATH"
chmod 600 "$KUBECONFIG_PATH"

log_info "k3s is Ready. Run: kubectl get nodes"
