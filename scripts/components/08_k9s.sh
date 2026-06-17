#!/bin/bash
# Installs the k9s TUI (ARM64 binary) — zero cluster resource cost.
# k9s reads ~/.kube/config and connects to any cluster locally or over SSH.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../lib/common.sh"
source "$SCRIPT_DIR/../config.sh"

require_root

INSTALL_DIR="/usr/local/bin"

if command_exists k9s; then
    log_info "k9s $(k9s version --short 2>/dev/null || k9s version) already installed — skipping."
    exit 0
fi

log_info "Detecting latest k9s release..."
if [[ "$K9S_VERSION" == "latest" ]]; then
    K9S_TAG=$(curl -fsSL https://api.github.com/repos/derailed/k9s/releases/latest \
        | grep '"tag_name"' | cut -d'"' -f4)
else
    K9S_TAG="$K9S_VERSION"
fi

ARCH=$(uname -m)
case "$ARCH" in
    aarch64|arm64) ARCH_LABEL="arm64" ;;
    armv7l)        ARCH_LABEL="arm" ;;
    x86_64)        ARCH_LABEL="amd64" ;;
    *)             die "Unsupported architecture: $ARCH" ;;
esac

TARBALL="k9s_Linux_${ARCH_LABEL}.tar.gz"
URL="https://github.com/derailed/k9s/releases/download/${K9S_TAG}/${TARBALL}"

log_info "Downloading k9s ${K9S_TAG} (${ARCH_LABEL})..."
curl -fsSL "$URL" -o "/tmp/${TARBALL}"
tar -xzf "/tmp/${TARBALL}" -C /tmp k9s
mv /tmp/k9s "$INSTALL_DIR/k9s"
chmod +x "$INSTALL_DIR/k9s"
rm -f "/tmp/${TARBALL}"

REAL_USER="${SUDO_USER:-$USER}"
REAL_HOME=$(eval echo "~$REAL_USER")

# Pre-create k9s state dir owned by the real user so it is never created by root.
K9S_STATE_DIR="$REAL_HOME/.local/state/k9s"
mkdir -p "$K9S_STATE_DIR"
chown -R "$REAL_USER:$REAL_USER" "$K9S_STATE_DIR"

log_info "k9s ${K9S_TAG} installed at ${INSTALL_DIR}/k9s"
log_info "Usage: k9s   (reads KUBECONFIG or ~/.kube/config)"
