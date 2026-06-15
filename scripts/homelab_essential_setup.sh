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

# The user who invoked sudo — needed for NVM (per-user install) and chown.
# When you run `sudo bash script.sh`, $USER becomes root and $SUDO_USER
# holds the original caller. Falls back to $USER when not using sudo.
REAL_USER="${SUDO_USER:-$USER}"

# Project root — one level above scripts/
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

log_info "========================================================"
log_info " Homelab Essential Setup"
log_info "========================================================"

log_info "--- Step 1/4: System dependencies ---"
bash "$SCRIPT_DIR/components/01_system_deps.sh"

log_info "--- Step 2/4: Python ${PYTHON_VERSIONS[*]} ---"
bash "$SCRIPT_DIR/components/02_python.sh"

# NVM must install as the real user — it writes to ~/.nvm and modifies ~/.bashrc.
log_info "--- Step 3/4: NVM + Node.js (as ${REAL_USER}) ---"
sudo -u "$REAL_USER" bash "$SCRIPT_DIR/components/03_nvm_node.sh"

log_info "--- Step 4/4: Docker + Compose v2 ---"
bash "$SCRIPT_DIR/components/04_docker.sh"

log_info "--- Creating .venv at ${PROJECT_DIR}/.venv ---"
PYTHON_BIN="/usr/local/bin/python3.11"
"$PYTHON_BIN" -m venv "$PROJECT_DIR/.venv"
chown -R "$REAL_USER:$REAL_USER" "$PROJECT_DIR/.venv"

log_info "========================================================"
log_info " Essential setup complete!"
log_info "========================================================"
log_info "Activate the project venv:  source ${PROJECT_DIR}/.venv/bin/activate"
log_info "Docker Compose:             docker compose ..."
log_info ""
log_info "IMPORTANT: Restart the Pi before running the cluster setup:"
log_info "  sudo reboot"
log_info "========================================================"
