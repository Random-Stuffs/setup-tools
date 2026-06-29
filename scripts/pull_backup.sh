#!/bin/bash
# Pulls the latest encrypted Gitea backup from the Raspberry Pi to this host.
# Run manually: bash scripts/pull_backup.sh
# Keeps the last LOCAL_RETAIN_COUNT encrypted backups locally.

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/common.sh"
source "$SCRIPT_DIR/config.sh"

PI_HOST="${PI_HOST:-$BACKUP_PI_HOST}"
[[ -z "$PI_HOST" ]] && die "PI_HOST not set — configure BACKUP_PI_HOST in config.sh or export PI_HOST=user@host"

mkdir -p "$LOCAL_BACKUP_DIR"

log_info "Connecting to $PI_HOST — looking for latest backup..."
LATEST=$(ssh "$PI_HOST" "ls -1t $BACKUP_DIR/*.tar.gz.gpg 2>/dev/null | head -1")
[[ -z "$LATEST" ]] && die "No encrypted backups found on $PI_HOST:$BACKUP_DIR"

FILENAME=$(basename "$LATEST")

if [[ -f "$LOCAL_BACKUP_DIR/$FILENAME" ]]; then
    log_info "Already have $FILENAME locally — nothing to do."
    exit 0
fi

log_info "Pulling $FILENAME..."
scp "$PI_HOST:$LATEST" "$LOCAL_BACKUP_DIR/$FILENAME"
log_info "Saved → $LOCAL_BACKUP_DIR/$FILENAME (size: $(du -sh "$LOCAL_BACKUP_DIR/$FILENAME" | cut -f1))"

# Rotate: keep only LOCAL_RETAIN_COUNT backups
BACKUPS=$(ls -1t "$LOCAL_BACKUP_DIR"/*.tar.gz.gpg 2>/dev/null || true)
COUNT=$(echo "$BACKUPS" | grep -c . || true)
if (( COUNT > LOCAL_RETAIN_COUNT )); then
    echo "$BACKUPS" | tail -n +"$(( LOCAL_RETAIN_COUNT + 1 ))" | xargs rm -f
    log_info "Pruned $(( COUNT - LOCAL_RETAIN_COUNT )) old local backup(s). Keeping $LOCAL_RETAIN_COUNT."
fi

log_info "Done. Local backups: $(ls -1 "$LOCAL_BACKUP_DIR"/*.tar.gz.gpg 2>/dev/null | wc -l)/$LOCAL_RETAIN_COUNT"
