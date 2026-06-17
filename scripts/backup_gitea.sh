#!/bin/bash
# Backs up Gitea data (SQLite DB + repos + packages) via kubectl cp.
# Runs as the regular user (not root) — kubectl must be configured.
# Invoked by cron; install with: bash scripts/setup_backup_cron.sh
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/common.sh"
source "$SCRIPT_DIR/config.sh"

export KUBECONFIG="$HOME/.kube/config"

TIMESTAMP=$(date +%Y%m%d_%H%M%S)
DEST="$BACKUP_DIR/$TIMESTAMP"

POD=$(kubectl get pod -n apps -l app=gitea -o name 2>/dev/null | cut -d/ -f2)
[[ -z "$POD" ]] && die "Gitea pod not found — is k3s running?"

log_info "Backing up Gitea (pod: $POD) → $DEST"
mkdir -p "$DEST"
kubectl cp "apps/$POD:/data" "$DEST"
log_info "Backup complete: $DEST ($(du -sh "$DEST" | cut -f1))"

# Rotation: keep only the last BACKUP_RETAIN_COUNT backups
BACKUPS=$(ls -1dt "$BACKUP_DIR"/[0-9]* 2>/dev/null || true)
COUNT=$(echo "$BACKUPS" | grep -c . || true)
if (( COUNT > BACKUP_RETAIN_COUNT )); then
    echo "$BACKUPS" | tail -n +"$((BACKUP_RETAIN_COUNT + 1))" | xargs rm -rf
    log_info "Pruned $((COUNT - BACKUP_RETAIN_COUNT)) old backup(s)."
fi
