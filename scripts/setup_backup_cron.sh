#!/bin/bash
# Installs a daily cron entry (05:00) to back up Gitea data.
# Run as the regular user (not root): bash scripts/setup_backup_cron.sh
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BACKUP_SCRIPT="$SCRIPT_DIR/backup_gitea.sh"
LOG_DIR="$HOME/backups/gitea"
LOG_FILE="$LOG_DIR/backup.log"
CRON_ENTRY="0 5 * * * $BACKUP_SCRIPT >> $LOG_FILE 2>&1"

mkdir -p "$LOG_DIR"
chmod +x "$BACKUP_SCRIPT"

if crontab -l 2>/dev/null | grep -qF "$BACKUP_SCRIPT"; then
    echo "Cron entry already installed — skipping."
else
    (crontab -l 2>/dev/null; echo "$CRON_ENTRY") | crontab -
    echo "Cron installed: runs daily at 05:00"
    echo "Log: $LOG_FILE"
fi

echo ""
echo "Test manually: bash $BACKUP_SCRIPT"
echo "View backups:  ls -lh $LOG_DIR"
echo "View log:      tail -f $LOG_FILE"
