#!/bin/bash
# Central configuration — edit this file to customise the homelab setup.
# All component scripts source this file automatically.

# --- Python ---
# Versions to build from source. Each entry is a full x.y.z tag.
# Add more versions here or pass them as arguments to 02_python.sh directly:
#   sudo bash scripts/components/02_python.sh 3.12.7 3.13.0
PYTHON_VERSIONS=("3.11.8")

# --- Node.js ---
NVM_VERSION="0.39.7"
NODE_VERSION="--lts"

# --- Docker ---
DOCKER_LOG_MAX_SIZE="10m"
DOCKER_LOG_MAX_FILES="3"

# --- k3s ---
# Leave empty to install the latest stable release.
K3S_VERSION=""
KUBECONFIG_PATH="$HOME/.kube/config"

# --- Helm ---
HELM_VERSION="latest"   # or pin, e.g. "v3.14.4"

# --- Gitea Runner ---
GITEA_RUNNER_NAMESPACE="ci"

# --- k9s ---
K9S_VERSION="latest"   # or pin, e.g. "v0.32.5"

# --- Backup ---
BACKUP_DIR="$HOME/backups/gitea"
BACKUP_RETAIN_COUNT=15   # number of daily backups to keep

# GPG recipient (email or fingerprint) used to encrypt backups.
# Run scripts/setup_backup_encryption.sh to generate the key pair.
# Leave empty to disable encryption (backup saved as .PLAIN.tar.gz).
GPG_RECIPIENT=""
