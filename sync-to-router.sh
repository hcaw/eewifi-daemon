#!/bin/bash
#
# Sync EE WiFi scripts to FreshTomato router
# Usage: ./sync-to-router.sh [router-ip]
#

set -e

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
ROUTER_IP="${1:-${ROUTER_IP:-192.168.1.1}}"
ROUTER_USER="${ROUTER_USER:-root}"
ROUTER_PATH="/jffs"

# Files to sync
SCRIPTS=(
    "eewifi-daemon.sh"
    "eewifi-service.sh"
    "uplink_status.sh"
    "wireless-monitor.sh"
    "internet-monitor.sh"
    "enable-wireless-debug.sh"
    "reconnect-wifi.sh"
)

# Colours for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No colour

echo -e "${GREEN}=== EE WiFi Router Sync ===${NC}"
echo "Target: ${ROUTER_USER}@${ROUTER_IP}:${ROUTER_PATH}"
echo ""

# Check if sshpass is available
if ! command -v sshpass &> /dev/null; then
    echo -e "${RED}Error: sshpass is required but not installed${NC}"
    echo "Install with: brew install hudochenkov/sshpass/sshpass"
    exit 1
fi

# Function to run remote command
remote_cmd() {
    sshpass -e ssh -o StrictHostKeyChecking=no "${ROUTER_USER}@${ROUTER_IP}" "$@"
}

# Function to copy file
copy_file() {
    local file=$1
    echo -n "Copying ${file}... "
    # Use -O flag for legacy SCP protocol (BusyBox doesn't have sftp-server)
    if sshpass -e scp -O -o StrictHostKeyChecking=no "$file" "${ROUTER_USER}@${ROUTER_IP}:${ROUTER_PATH}/" 2>/dev/null; then
        echo -e "${GREEN}✓${NC}"
        return 0
    else
        echo -e "${RED}✗${NC}"
        return 1
    fi
}

# Check if daemon is running
echo "Checking daemon status..."
if remote_cmd "[ -f /var/run/eewifi-daemon.pid ] && [ -d /proc/\$(cat /var/run/eewifi-daemon.pid) ]" 2>/dev/null; then
    DAEMON_RUNNING=true
    DAEMON_PID=$(remote_cmd "cat /var/run/eewifi-daemon.pid" 2>/dev/null)
    echo -e "${YELLOW}Daemon is running (PID: ${DAEMON_PID})${NC}"
else
    DAEMON_RUNNING=false
    echo "Daemon is not running"
fi
echo ""

# Copy files
echo "Copying files to router..."
FAILED=0
for script in "${SCRIPTS[@]}"; do
    if [ -f "$script" ]; then
        copy_file "$script" || FAILED=$((FAILED + 1))
    else
        echo -e "${YELLOW}Warning: ${script} not found, skipping${NC}"
    fi
done
echo ""

if [ $FAILED -gt 0 ]; then
    echo -e "${RED}Failed to copy ${FAILED} file(s)${NC}"
    exit 1
fi

# Set executable permissions
echo "Setting permissions..."
remote_cmd "chmod +x ${ROUTER_PATH}/*.sh 2>/dev/null"
echo -e "${GREEN}✓ Permissions set${NC}"
echo ""

# Restart daemon if it was running
if [ "$DAEMON_RUNNING" = true ]; then
    echo -e "${YELLOW}Restarting daemon...${NC}"
    if remote_cmd "${ROUTER_PATH}/eewifi-service.sh stop" 2>/dev/null; then
        sleep 2
        if remote_cmd "${ROUTER_PATH}/eewifi-service.sh start" 2>/dev/null; then
            NEW_PID=$(remote_cmd "cat /var/run/eewifi-daemon.pid" 2>/dev/null)
            echo -e "${GREEN}✓ Daemon restarted (PID: ${NEW_PID})${NC}"
        else
            echo -e "${RED}✗ Failed to restart daemon${NC}"
            exit 1
        fi
    else
        echo -e "${YELLOW}Note: Daemon wasn't running via service, you may need to restart manually${NC}"
    fi
else
    echo -e "${YELLOW}Note: Daemon not running. Start with: ${ROUTER_PATH}/eewifi-service.sh start${NC}"
fi

echo ""
echo -e "${GREEN}=== Sync complete ===${NC}"
echo ""
echo "View logs with:"
echo "  ssh root@${ROUTER_IP} 'tail -f /var/log/messages | grep eewifi'"
