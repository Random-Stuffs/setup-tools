#!/bin/bash
# Shared helpers sourced by all component scripts.

log_info()  { echo "[INFO]  $*"; }
log_warn()  { echo "[WARN]  $*" >&2; }
log_error() { echo "[ERROR] $*" >&2; }

# Exit with an error message.
die() { log_error "$*"; exit 1; }

# Abort if not running as root/sudo.
require_root() {
    [[ $EUID -eq 0 ]] || die "This script must be run with sudo or as root."
}

# Return 0 if a command exists in PATH.
command_exists() { command -v "$1" &>/dev/null; }

# Resolve the directory of the sourcing script (not this file).
scripts_dir() { dirname "$(realpath "${BASH_SOURCE[1]}")" ; }
