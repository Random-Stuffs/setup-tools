#!/bin/bash
# Generates a GPG key pair for Gitea backup encryption.
# Run as the regular user (not root): bash scripts/setup_backup_encryption.sh
#
# Security model:
#   - Private key is exported and then REMOVED from this machine's keyring.
#   - The Pi retains only the public key — it can encrypt but never decrypt.
#   - Store the exported private key in a password manager or offline device.

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/common.sh"

KEY_EMAIL="gitea-backup@homelab.local"
KEY_NAME="Gitea Backup"
EXPORT_FILE="$HOME/gitea-backup-private-key.asc"

# --- Check if key already exists ---
if gpg --list-keys "$KEY_EMAIL" &>/dev/null; then
    log_info "Key already exists for $KEY_EMAIL — skipping generation."
else
    log_info "Generating GPG key pair (RSA 4096, no passphrase)..."
    gpg --batch --gen-key <<EOF
%no-protection
Key-Type: RSA
Key-Length: 4096
Subkey-Type: RSA
Subkey-Length: 4096
Name-Real: $KEY_NAME
Name-Email: $KEY_EMAIL
Expire-Date: 0
%commit
EOF
    log_info "Key generated."
fi

FINGERPRINT=$(gpg --list-keys --with-colons "$KEY_EMAIL" | awk -F: '/^fpr/{print $10; exit}')

# --- Export private key before removing it ---
log_info "Exporting private key → $EXPORT_FILE"
gpg --armor --export-secret-keys "$KEY_EMAIL" > "$EXPORT_FILE"
chmod 600 "$EXPORT_FILE"

# --- Remove private key: Pi only needs the public key to encrypt ---
log_info "Removing private key from local keyring (Pi encrypts-only from now on)..."
gpg --batch --yes --delete-secret-keys "$FINGERPRINT"

echo ""
echo "================================================================"
echo "  IMPORTANT: move the private key to a safe location NOW."
echo "  $EXPORT_FILE"
echo ""
echo "  Without it, encrypted backups CANNOT be restored."
echo "  Suggested: import into your password manager or store offline."
echo "================================================================"
echo ""
echo "Add this line to scripts/config.sh:"
echo "  GPG_RECIPIENT=\"$KEY_EMAIL\""
echo ""
echo "To decrypt a backup later (from a machine with the private key):"
echo "  gpg --import gitea-backup-private-key.asc"
echo "  gpg --decrypt backup_TIMESTAMP.tar.gz.gpg | tar -xz -C /restore/path"
