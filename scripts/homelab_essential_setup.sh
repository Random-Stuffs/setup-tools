#!/bin/bash
# =============================================================================
# Raspberry Pi OS — Essential Setup
# Installs: system deps | Python (from source) | Node.js (NVM) | Docker
#
# Usage:
#   sudo bash homelab_essential_setup.sh
#
# Individual components can also be run directly from scripts/components/.
# All configurable values (Python versions, Node version, etc.) are in config.sh.
# =============================================================================
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/common.sh"
source "$SCRIPT_DIR/config.sh"

require_root

log_info "========================================================"
log_info " Homelab Essential Setup"
log_info "========================================================"

log_info "--- Step 1/4: System dependencies ---"
bash "$SCRIPT_DIR/components/01_system_deps.sh"

log_info "--- Step 2/4: Python ${PYTHON_VERSIONS[*]} ---"
bash "$SCRIPT_DIR/components/02_python.sh"

# NVM installs per-user, must run as the real user (not root).
REAL_USER="${SUDO_USER:-$USER}"
log_info "--- Step 3/4: NVM + Node.js (running as ${REAL_USER}) ---"
sudo -u "$REAL_USER" bash "$SCRIPT_DIR/components/03_nvm_node.sh"

log_info "--- Step 4/4: Docker + Compose v2 ---"
bash "$SCRIPT_DIR/components/04_docker.sh"

log_info "--- Creating lab venv at ${LAB_DIR}/.venv ---"
PYTHON_BIN="/usr/local/bin/python${PYTHON_VERSIONS[-1]%.*}"  # use the last listed version
mkdir -p "$LAB_DIR"
sudo -u "$REAL_USER" "$PYTHON_BIN" -m venv "$LAB_DIR/.venv"

log_info "========================================================"
log_info " Essential setup complete!"
log_info "========================================================"
log_info "Available Python commands: ${PYTHON_VERSIONS[*]//.}"
log_info "Activate the lab venv:  source ${LAB_DIR}/.venv/bin/activate"
log_info "Docker Compose:         docker compose ..."
log_info ""
log_info "IMPORTANT: Restart the Pi before running the cluster setup:"
log_info "  sudo reboot"
log_info "========================================================"
