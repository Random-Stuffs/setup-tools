#!/bin/bash
# Installs Docker CE + Compose v2 plugin with SD-card-safe log rotation.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../lib/common.sh"
source "$SCRIPT_DIR/../config.sh"

require_root

if command_exists docker; then
    log_info "Docker $(docker --version) already installed — skipping install."
else
    log_info "Installing Docker via official script..."
    curl -fsSL https://get.docker.com | sh
fi

log_info "Adding ${SUDO_USER:-$USER} to the docker group..."
usermod -aG docker "${SUDO_USER:-$USER}"

log_info "Configuring Docker log rotation..."
mkdir -p /etc/docker
cat > /etc/docker/daemon.json <<EOF
{
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "${DOCKER_LOG_MAX_SIZE}",
    "max-file": "${DOCKER_LOG_MAX_FILES}"
  }
}
EOF
systemctl restart docker

log_info "Installing Docker Compose v2 plugin..."
apt-get install -y docker-compose-plugin

log_info "Docker $(docker --version) + Compose $(docker compose version) ready."
log_info "Log out and back in (or run 'newgrp docker') to use Docker without sudo."
