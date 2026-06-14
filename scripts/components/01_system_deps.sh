#!/bin/bash
# Installs all apt build dependencies needed by subsequent components.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../lib/common.sh"
source "$SCRIPT_DIR/../config.sh"

require_root

log_info "Updating package lists..."
apt-get update -y

log_info "Installing build dependencies and system tools..."
apt-get install -y \
    build-essential \
    zlib1g-dev \
    libncurses5-dev \
    libgdbm-dev \
    libnss3-dev \
    libssl-dev \
    libreadline-dev \
    libffi-dev \
    libsqlite3-dev \
    libxml2-dev \
    libxmlsec1-dev \
    libncursesw5-dev \
    liblzma-dev \
    llvm \
    tk-dev \
    xz-utils \
    wget \
    curl \
    git \
    python3-pip \
    python3-dev

log_info "Installing audio libraries..."
apt-get install -y \
    portaudio19-dev \
    python3-pyaudio \
    libasound2-dev \
    flac \
    mpg123

log_info "System dependencies installed."
