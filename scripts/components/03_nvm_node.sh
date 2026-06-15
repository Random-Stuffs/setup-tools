#!/bin/bash
# Installs NVM (Node Version Manager) and Node.js LTS for the current user.
# Must NOT be run as root — NVM installs per-user.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../lib/common.sh"
source "$SCRIPT_DIR/../config.sh"

if [[ $EUID -eq 0 ]]; then
    die "03_nvm_node.sh must be run as a regular user, not root."
fi

NVM_DIR="$HOME/.nvm"

if [[ -s "$NVM_DIR/nvm.sh" ]]; then
    log_info "NVM already installed at ${NVM_DIR} — skipping install."
else
    log_info "Installing NVM v${NVM_VERSION}..."
    curl -o- "https://raw.githubusercontent.com/nvm-sh/nvm/v${NVM_VERSION}/install.sh" | bash
fi

# Load NVM into this shell session.
export NVM_DIR
# shellcheck source=/dev/null
source "$NVM_DIR/nvm.sh"

log_info "Installing Node.js (${NODE_VERSION})..."
nvm install "$NODE_VERSION"
nvm use "$NODE_VERSION"
nvm alias default "$NODE_VERSION"

log_info "Node $(node --version) / npm $(npm --version) ready."
log_info "Restart your shell or run: source ~/.bashrc"
