#!/bin/sh
#
# EE WiFi Service Controller for FreshTomato
# Unified script for login, logout, status, and daemon control
#

# Location of config and daemon
CONFIG_FILE="/jffs/eewifi-daemon.config"
DAEMON_SCRIPT="/jffs/eewifi-daemon.sh"
PID_FILE="/var/run/eewifi-daemon.pid"

# Load config if available
if [ -f "$CONFIG_FILE" ]; then
    . "$CONFIG_FILE"
else
    echo "Warning: Config file not found at $CONFIG_FILE"
    echo "Some commands may not work without credentials."
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
        echo "Status: LOGGED IN"
        return 0
    else
        echo "Status: NOT LOGGED IN"
        return 1
    fi
}

# Perform login
do_login() {
    if [ -z "$USERNAME" ] || [ -z "$PASSWORD" ]; then
        echo "Error: USERNAME and PASSWORD must be set in $CONFIG_FILE"
        return 1
    fi

    echo "Attempting login as $USERNAME..."
    postdata="inputUsername=$USERNAME&username=wam/$USERNAME&password=$PASSWORD&xhtmlLogon=$SERVER/ante"

    # Send login request (may fail with redirect error but still work)
    fetch_url "$SERVER/ante" "$postdata" >/dev/null 2>&1

    # Brief pause then verify
    sleep 2

    if check_status >/dev/null 2>&1; then
        echo "Login successful!"
        return 0
    else
        echo "Login may have failed. Check status manually."
        return 1
    fi
}

# Perform logout
do_logout() {
    echo "Logging out..."
    fetch_url "$SERVER/accountLogoff/home?confirmed=true" >/dev/null 2>&1
    sleep 1

    if ! check_status >/dev/null 2>&1; then
        echo "Logout successful!"
        return 0
    else
        echo "Logout may have failed. Check status manually."
        return 1
    fi
}

# Start the daemon
daemon_start() {
    if [ -f "$PID_FILE" ]; then
        pid=$(cat "$PID_FILE")
        if [ -d "/proc/$pid" ]; then
            echo "Daemon already running (PID: $pid)"
            return 1
        else
            rm -f "$PID_FILE"
        fi
    fi

    if [ ! -x "$DAEMON_SCRIPT" ]; then
        echo "Error: Daemon script not found or not executable: $DAEMON_SCRIPT"
        return 1
    fi

    echo "Starting EE WiFi daemon..."
    $DAEMON_SCRIPT &
    daemon_pid=$!
    echo "$daemon_pid" > "$PID_FILE"
    sleep 1

    if [ -d "/proc/$daemon_pid" ]; then
        echo "Daemon started (PID: $daemon_pid)"
        return 0
    else
        echo "Failed to start daemon"
        rm -f "$PID_FILE"
        return 1
    fi
}

# Stop the daemon
daemon_stop() {
    if [ -f "$PID_FILE" ]; then
        pid=$(cat "$PID_FILE")
        if [ -d "/proc/$pid" ]; then
            echo "Stopping daemon (PID: $pid)..."
            kill "$pid" 2>/dev/null
            sleep 2
            if [ -d "/proc/$pid" ]; then
                kill -9 "$pid" 2>/dev/null
            fi
            rm -f "$PID_FILE"
            echo "Daemon stopped"
            return 0
        else
            echo "PID file exists but daemon not running"
            rm -f "$PID_FILE"
            return 1
        fi
    else
        echo "Daemon not running (no PID file)"
        return 1
    fi
}

# Check daemon status
daemon_status() {
    if [ -f "$PID_FILE" ]; then
        pid=$(cat "$PID_FILE")
        if [ -d "/proc/$pid" ]; then
            echo "Daemon: RUNNING (PID: $pid)"
            return 0
        else
            echo "Daemon: NOT RUNNING (stale PID file)"
            return 1
        fi
    else
        echo "Daemon: NOT RUNNING"
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
