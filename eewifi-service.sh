#!/bin/sh
#
# EE WiFi Service Controller for FreshTomato
# Unified script for login, logout, status, and daemon control
#

# Location of config and daemon
CONFIG_FILE="/jffs/eewifi-daemon.config"
DAEMON_SCRIPT="/jffs/eewifi-daemon.sh"
PID_FILE="/var/run/eewifi-daemon.pid"

# Logger configuration
LOGGER="/usr/bin/logger"
LOG_TAG="eewifi-service"

# Logging function - sends to syslog and optionally prints to stdout
# Usage: log_msg "message" [priority] [quiet]
# Priority: info (default), warn, err
# quiet: if set to "quiet", don't print to stdout
log_msg() {
    msg="$1"
    priority="${2:-info}"
    quiet="${3:-}"

    # Log to syslog
    if [ -x "$LOGGER" ]; then
        "$LOGGER" -t "$LOG_TAG" -p "daemon.$priority" "$msg"
    fi

    # Also print to stdout unless quiet mode
    if [ "$quiet" != "quiet" ]; then
        echo "$msg"
    fi
}

# Load config if available
if [ -f "$CONFIG_FILE" ]; then
    . "$CONFIG_FILE"
else
    log_msg "Warning: Config file not found at $CONFIG_FILE" "warn"
    log_msg "Some commands may not work without credentials." "warn"
fi

# Default server if not in config
SERVER="${SERVER:-https://ee-wifi.ee.co.uk}"

#######################
# FUNCTIONS
#######################

# fetch_url: Uses curl if available, falls back to wget
# Usage: fetch_url <url> [postdata]
fetch_url() {
    url=$1
    postdata=$2
    timeout=${WGET_TIMEOUT:-10}

    if which curl >/dev/null 2>&1; then
        if [ -n "$postdata" ]; then
            curl -sS -k --max-time "$timeout" -d "$postdata" "$url" 2>/dev/null
        else
            curl -sS -k --max-time "$timeout" "$url" 2>/dev/null
        fi
    else
        if [ -n "$postdata" ]; then
            wget -qO - --no-check-certificate -T "$timeout" --post-data "$postdata" "$url" 2>/dev/null
        else
            wget -qO - --no-check-certificate -T "$timeout" "$url" 2>/dev/null
        fi
    fi
}

# Check current login status
check_status() {
    response=$(fetch_url "$SERVER/home")
    if printf "%s" "$response" | grep -q "You are now connected"; then
        log_msg "Status: LOGGED IN" "info"
        return 0
    else
        log_msg "Status: NOT LOGGED IN" "info"
        return 1
    fi
}

# Perform login
do_login() {
    if [ -z "$USERNAME" ] || [ -z "$PASSWORD" ]; then
        log_msg "Error: USERNAME and PASSWORD must be set in $CONFIG_FILE" "err"
        return 1
    fi

    log_msg "Attempting manual login as $USERNAME" "info"
    postdata="inputUsername=$USERNAME&username=wam/$USERNAME&password=$PASSWORD&xhtmlLogon=$SERVER/ante"

    # Send login request (may fail with redirect error but still work)
    fetch_url "$SERVER/ante" "$postdata" >/dev/null 2>&1

    # Brief pause then verify
    sleep 2

    if check_status >/dev/null 2>&1; then
        log_msg "Login successful for user $USERNAME" "info"
        return 0
    else
        log_msg "Login may have failed. Check status manually." "warn"
        return 1
    fi
}

# Perform logout
do_logout() {
    log_msg "Logging out from EE WiFi" "info"
    fetch_url "$SERVER/accountLogoff/home?confirmed=true" >/dev/null 2>&1
    sleep 1

    if ! check_status >/dev/null 2>&1; then
        log_msg "Logout successful" "info"
        return 0
    else
        log_msg "Logout may have failed. Check status manually." "warn"
        return 1
    fi
}

# Start the daemon
daemon_start() {
    if [ -f "$PID_FILE" ]; then
        pid=$(cat "$PID_FILE")
        if [ -d "/proc/$pid" ]; then
            log_msg "Daemon already running (PID: $pid)" "warn"
            return 1
        else
            rm -f "$PID_FILE"
        fi
    fi

    if [ ! -x "$DAEMON_SCRIPT" ]; then
        log_msg "Error: Daemon script not found or not executable: $DAEMON_SCRIPT" "err"
        return 1
    fi

    log_msg "Starting EE WiFi daemon" "info"
    $DAEMON_SCRIPT &
    daemon_pid=$!
    echo "$daemon_pid" > "$PID_FILE"
    sleep 1

    if [ -d "/proc/$daemon_pid" ]; then
        log_msg "Daemon started successfully (PID: $daemon_pid)" "info"
        return 0
    else
        log_msg "Failed to start daemon" "err"
        rm -f "$PID_FILE"
        return 1
    fi
}

# Stop the daemon
daemon_stop() {
    if [ -f "$PID_FILE" ]; then
        pid=$(cat "$PID_FILE")
        if [ -d "/proc/$pid" ]; then
            log_msg "Stopping daemon (PID: $pid)" "info"
            kill "$pid" 2>/dev/null
            sleep 2
            if [ -d "/proc/$pid" ]; then
                kill -9 "$pid" 2>/dev/null
            fi
            rm -f "$PID_FILE"
            log_msg "Daemon stopped successfully" "info"
            return 0
        else
            log_msg "PID file exists but daemon not running, cleaning up" "warn"
            rm -f "$PID_FILE"
            return 1
        fi
    else
        log_msg "Daemon not running (no PID file)" "info"
        return 1
    fi
}

# Check daemon status
daemon_status() {
    if [ -f "$PID_FILE" ]; then
        pid=$(cat "$PID_FILE")
        if [ -d "/proc/$pid" ]; then
            log_msg "Daemon: RUNNING (PID: $pid)" "info"
            return 0
        else
            log_msg "Daemon: NOT RUNNING (stale PID file)" "info"
            return 1
        fi
    else
        log_msg "Daemon: NOT RUNNING" "info"
        return 1
    fi
}

# Get current SSID (FreshTomato/Broadcom)
get_ssid() {
    if which wl >/dev/null 2>&1; then
        for iface in eth1 eth2 wl0 wl1; do
            # Get SSID: strip prefix and optional quotes (preserves spaces in SSID)
            ssid=$(wl -i "$iface" status 2>/dev/null | grep '^SSID:' | sed 's/^SSID: *"\{0,1\}//; s/"\{0,1\}$//')
            if [ -n "$ssid" ]; then
                echo "$ssid"
                return 0
            fi
        done
    fi
    echo "Unknown"
    return 1
}

# Show full info
show_info() {
    echo "=== EE WiFi Service Info ==="
    echo "SSID: $(get_ssid)"
    check_status
    daemon_status
    echo "Config: $CONFIG_FILE"
    echo "Server: $SERVER"
    if [ -n "$USERNAME" ]; then
        echo "User: $USERNAME"
    fi
    log_msg "Service info requested" "info" "quiet"
}

# Usage
usage() {
    cat <<EOF
EE WiFi Service Controller

Usage: $0 <command>

Commands:
  login     - Login to EE WiFi
  logout    - Logout from EE WiFi
  status    - Check login status
  info      - Show full service info

  start     - Start the auto-login daemon
  stop      - Stop the daemon
  restart   - Restart the daemon
  daemon    - Check daemon status

EOF
}

#######################
# MAIN
#######################

case "${1:-}" in
    login)
        do_login
        ;;
    logout)
        do_logout
        ;;
    status)
        check_status
        ;;
    info)
        show_info
        ;;
    start)
        daemon_start
        ;;
    stop)
        daemon_stop
        ;;
    restart)
        daemon_stop
        sleep 1
        daemon_start
        ;;
    daemon)
        daemon_status
        ;;
    *)
        usage
        exit 1
        ;;
esac
