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

# ---------------------------------------------------------------------------
# Raspberry Pi cgroup fix
# k3s requires the memory cgroup controller to be enabled at boot.
# On Raspberry Pi OS it is off by default, causing:
#   "Error: failed to find memory cgroup (v2)"
# Fix: inject the required params into cmdline.txt and flag for reboot.
# ---------------------------------------------------------------------------
fix_cgroups() {
    # Pi OS Bookworm uses /boot/firmware/cmdline.txt; older releases use /boot/cmdline.txt
    local cmdline
    if [[ -f /boot/firmware/cmdline.txt ]]; then
        cmdline=/boot/firmware/cmdline.txt
    elif [[ -f /boot/cmdline.txt ]]; then
        cmdline=/boot/cmdline.txt
    else
        log_warn "Could not find cmdline.txt — skipping cgroup fix."
        return 0
    fi

    local needed="cgroup_enable=cpuset cgroup_enable=memory cgroup_memory=1"
    local current
    current=$(cat "$cmdline")
    local updated="$current"
    local changed=0

    for param in $needed; do
        if ! grep -q "$param" "$cmdline"; then
            updated="$updated $param"
            changed=1
        fi
    done

    if [[ $changed -eq 1 ]]; then
        log_info "Enabling cgroup memory in ${cmdline}..."
        # cmdline.txt must be a single line — write atomically
        echo "$updated" > "$cmdline"
        log_warn "cgroup params added. A REBOOT IS REQUIRED before k3s will start."
        log_warn "Run: sudo reboot — then re-run this script."
        exit 0
    else
        log_info "cgroup memory already enabled in ${cmdline}."
    fi
}

fix_cgroups

install_k3s() {
    log_info "Installing k3s (containerd runtime)..."
    # K3S_KUBECONFIG_MODE=644 makes /etc/rancher/k3s/k3s.yaml world-readable
    # so kubectl works without sudo even before we copy it to ~/.kube/config.
    if [[ -n "$K3S_VERSION" ]]; then
        curl -sfL https://get.k3s.io | K3S_KUBECONFIG_MODE=644 INSTALL_K3S_VERSION="$K3S_VERSION" sh -
    else
        curl -sfL https://get.k3s.io | K3S_KUBECONFIG_MODE=644 sh -
    fi
}

setup_kubeconfig() {
    local kube_dir
    kube_dir="$(dirname "$KUBECONFIG_PATH")"

    log_info "Configuring kubeconfig for ${REAL_USER}..."
    # Create ~/.kube owned by the real user, not root.
    mkdir -p "$kube_dir"
    chown "$REAL_USER:$REAL_USER" "$kube_dir"

    cp /etc/rancher/k3s/k3s.yaml "$KUBECONFIG_PATH"
    chown "$REAL_USER:$REAL_USER" "$KUBECONFIG_PATH"
    chmod 600 "$KUBECONFIG_PATH"

    log_info "kubeconfig written to ${KUBECONFIG_PATH}."
}

if command_exists k3s; then
    # Detect broken install: binary present but service not active.
    if ! systemctl is-active --quiet k3s; then
        log_warn "k3s binary found but service is not running (broken install detected)."
        log_info "Running k3s-uninstall.sh to clean up..."
        /usr/local/bin/k3s-uninstall.sh
        install_k3s
    else
        log_info "k3s $(k3s --version | head -1) already installed and running — skipping."
    fi
else
    install_k3s
fi

log_info "Waiting for k3s node to become Ready (timeout: 90s)..."
SECONDS=0
until k3s kubectl get nodes 2>/dev/null | grep -q " Ready"; do
    if (( SECONDS > 90 )); then
        log_error "k3s did not become Ready within 90s."
        log_error "Check logs with: sudo journalctl -u k3s --no-pager -n 40"
        exit 1
    fi
    sleep 3
done

setup_kubeconfig

log_info "k3s is Ready. Run: kubectl get nodes"
