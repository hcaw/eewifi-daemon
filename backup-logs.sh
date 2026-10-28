#!/bin/bash
#
# Backup router logs to local machine
# Run via cron: */30 * * * * ~/backup-logs.sh
#

# Settings (ROUTER_IP, ROUTER_USER, ROUTER_PASS) come from .env next to this script.
# Copy .env.example to .env and fill it in. .env is gitignored; never commit it.
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ENV_FILE="${ENV_FILE:-$SCRIPT_DIR/.env}"
if [ ! -f "$ENV_FILE" ]; then
    echo "Error: $ENV_FILE not found. Copy .env.example to .env and set ROUTER_PASS." >&2
    exit 1
fi
set -a
. "$ENV_FILE"
set +a
if [ -z "${ROUTER_PASS:-}" ]; then
    echo "Error: ROUTER_PASS is not set in $ENV_FILE" >&2
    exit 1
fi
export SSHPASS="$ROUTER_PASS"
ROUTER_IP="${ROUTER_IP:-192.168.1.1}"
ROUTER_USER="${ROUTER_USER:-root}"
BACKUP_DIR="$HOME/router-logs"
DATE=$(date +%Y%m%d-%H%M%S)

mkdir -p "$BACKUP_DIR"

echo "=== Router Log Backup - $DATE ==="

# Backup all log files
sshpass -e ssh -o StrictHostKeyChecking=no "${ROUTER_USER}@${ROUTER_IP}" \
    "tar czf - /var/log/messages* /jffs/logs/messages* 2>/dev/null" > \
    "$BACKUP_DIR/router-logs-${DATE}.tar.gz"

if [ $? -eq 0 ]; then
    SIZE=$(ls -lh "$BACKUP_DIR/router-logs-${DATE}.tar.gz" | awk '{print $5}')
    echo "✓ Backed up to $BACKUP_DIR/router-logs-${DATE}.tar.gz ($SIZE)"

    # Keep only last 100 backups
    ls -t "$BACKUP_DIR"/router-logs-*.tar.gz | tail -n +101 | xargs rm -f 2>/dev/null
else
    echo "✗ Backup failed"
    rm -f "$BACKUP_DIR/router-logs-${DATE}.tar.gz"
fi
