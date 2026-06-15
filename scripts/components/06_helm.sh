#!/bin/bash
# Installs Helm 3.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../lib/common.sh"
source "$SCRIPT_DIR/../config.sh"

require_root

if command_exists helm; then
    log_info "Helm $(helm version --short) already installed — skipping."
    exit 0
fi

log_info "Installing Helm..."
curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash

log_info "Helm $(helm version --short) installed."
