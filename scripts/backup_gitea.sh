#!/bin/bash
# Backs up Gitea data (SQLite DB + repos + packages) via kubectl cp.
# Runs as the regular user (not root) — kubectl must be configured.
# Invoked by cron; install with: bash scripts/setup_backup_cron.sh
#
# Output files:
#   <timestamp>.tar.gz.gpg   — encrypted (when GPG_RECIPIENT is set and works)
#   <timestamp>.PLAIN.tar.gz — unencrypted fallback (no key configured or GPG failed)
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/common.sh"
source "$SCRIPT_DIR/config.sh"

export KUBECONFIG="$HOME/.kube/config"

TIMESTAMP=$(date +%Y%m%d_%H%M%S)
DEST="$BACKUP_DIR/$TIMESTAMP"
TAR_FILE="$DEST.tar.gz"

POD=$(kubectl get pod -n apps -l app=gitea -o name 2>/dev/null | cut -d/ -f2)
[[ -z "$POD" ]] && die "Gitea pod not found — is k3s running?"

log_info "Backing up Gitea (pod: $POD) → $DEST"
mkdir -p "$DEST"
kubectl cp "apps/$POD:/data" "$DEST"

# Package into a single archive (directory is removed afterwards)
tar -czf "$TAR_FILE" -C "$BACKUP_DIR" "$TIMESTAMP"
rm -rf "$DEST"

# --- Encryption ---
FINAL_FILE=""
if [[ -n "${GPG_RECIPIENT:-}" ]]; then
    ENCRYPTED_FILE="${TAR_FILE}.gpg"
    if gpg --batch --yes --encrypt --recipient "$GPG_RECIPIENT" "$TAR_FILE" 2>/dev/null; then
        rm -f "$TAR_FILE"
        FINAL_FILE="$ENCRYPTED_FILE"
        log_info "Backup encrypted: $FINAL_FILE ($(du -sh "$FINAL_FILE" | cut -f1))"
    else
        PLAIN_FILE="${DEST}.PLAIN.tar.gz"
        mv "$TAR_FILE" "$PLAIN_FILE"
        FINAL_FILE="$PLAIN_FILE"
        log_warn "GPG encryption failed — backup saved unencrypted: $FINAL_FILE"
    fi
else
    PLAIN_FILE="${DEST}.PLAIN.tar.gz"
    mv "$TAR_FILE" "$PLAIN_FILE"
    FINAL_FILE="$PLAIN_FILE"
    log_info "No GPG_RECIPIENT configured — backup saved unencrypted: $FINAL_FILE"
fi

# --- Rotation: keep only the last BACKUP_RETAIN_COUNT backups ---
BACKUPS=$(ls -1dt "$BACKUP_DIR"/[0-9]*.tar.gz* 2>/dev/null || true)
COUNT=$(echo "$BACKUPS" | grep -c . || true)
if (( COUNT > BACKUP_RETAIN_COUNT )); then
    echo "$BACKUPS" | tail -n +"$((BACKUP_RETAIN_COUNT + 1))" | xargs rm -f
    log_info "Pruned $((COUNT - BACKUP_RETAIN_COUNT)) old backup(s)."
fi
