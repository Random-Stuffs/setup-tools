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

# --- ARC (Actions Runner Controller) ---
ARC_CHART_VERSION="0.13.1"
GITHUB_CONFIG_URL="https://github.com/Random-Stuffs"   # org or repo URL
GITHUB_RUNNER_NAMESPACE="ci"
GITHUB_RUNNER_NAME="homelab-runner"
# GITHUB_PAT must be set in the environment before running 07_arc.sh:
#   export GITHUB_PAT="ghp_..."

# --- k9s ---
K9S_VERSION="latest"   # or pin, e.g. "v0.32.5"
