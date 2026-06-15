#!/bin/bash
# Builds and installs Python versions from source.
#
# Usage:
#   sudo bash 02_python.sh              # uses PYTHON_VERSIONS from config.sh
#   sudo bash 02_python.sh 3.13.2       # installs a single version
#   sudo bash 02_python.sh 3.12.9 3.11.9 # installs multiple specified versions
#
# Each version is installed via `make altinstall`, creating:
#   /usr/local/bin/python3.XX   (e.g. python3.13)
#   /usr/local/bin/pip3.XX
#
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../lib/common.sh"
source "$SCRIPT_DIR/../config.sh"

require_root

# Resolve version list: CLI args take precedence over config.sh array.
if [[ $# -gt 0 ]]; then
    VERSIONS=("$@")
else
    VERSIONS=("${PYTHON_VERSIONS[@]}")
fi

install_python() {
    local full_ver="$1"
    local minor="${full_ver%.*}"           # e.g. "3.13" from "3.13.0"
    local alias="python${minor//./}"       # e.g. "python313"
    local bin="/usr/local/bin/python${minor}"

    if [[ -x "$bin" ]]; then
        log_info "Python ${minor} already installed at ${bin} — skipping."
        return 0
    fi

    log_info "Building Python ${full_ver} from source (this takes several minutes)..."
    cd /tmp
    wget -q "https://www.python.org/ftp/python/${full_ver}/Python-${full_ver}.tar.xz"
    tar -xf "Python-${full_ver}.tar.xz"
    cd "Python-${full_ver}"

    ./configure --enable-optimizations --quiet
    make -j"$(nproc)" --quiet
    make altinstall --quiet

    # Short alias: python311, python312, python313 …
    ln -sf "$bin" "/usr/local/bin/${alias}"

    # Cleanup build artefacts to save space on the SD card / SSD.
    cd /tmp && rm -rf "Python-${full_ver}" "Python-${full_ver}.tar.xz"

    log_info "Python ${full_ver} installed → ${bin} (alias: ${alias})"
}

for ver in "${VERSIONS[@]}"; do
    install_python "$ver"
done

log_info "All requested Python versions installed."
