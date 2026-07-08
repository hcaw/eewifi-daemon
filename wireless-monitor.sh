#!/bin/sh
#
# Wireless Connection Monitor for FreshTomato
# Tracks wireless client connection state and logs changes
#
# Add to cron: */1 * * * * /jffs/wireless-monitor.sh
#

# Configuration
STATE_FILE="/var/run/wireless-monitor.state"
LOGGER="/usr/bin/logger"
LOG_TAG="wireless-monitor"
WL_IFACE="eth2"  # 5GHz wireless client (uplink) interface

# Logging function
log_msg() {
    msg="$1"
    priority="${2:-info}"
    if [ -x "$LOGGER" ]; then
        "$LOGGER" -t "$LOG_TAG" -p "daemon.$priority" "$msg"
    fi
}

# Get current wireless status
get_wireless_status() {
    if ! which wl >/dev/null 2>&1; then
        log_msg "wl utility not found" "err"
        exit 1
    fi

    # Get connection details
    WL_STATUS=$(wl -i "$WL_IFACE" status 2>/dev/null)

    # Parse SSID
    CURRENT_SSID=$(echo "$WL_STATUS" | sed -n 's/^SSID: *"\(.*\)"/\1/p')

    # Parse Channel
    CURRENT_CHANNEL=$(echo "$WL_STATUS" | sed -n 's/.*Channel: *\([0-9]*\).*/\1/p')

    # Get BSSID
    CURRENT_BSSID=$(wl -i "$WL_IFACE" bssid 2>/dev/null | awk '{print $NF}')

    # Get RSSI
    CURRENT_RSSI=$(wl -i "$WL_IFACE" rssi 2>/dev/null | tr -d ' ')

    # Get interface IP
    CURRENT_IP=$(ifconfig "$WL_IFACE" 2>/dev/null | grep 'inet addr' | awk '{print $2}' | cut -d: -f2)
    [ -z "$CURRENT_IP" ] && CURRENT_IP=$(ip addr show "$WL_IFACE" 2>/dev/null | grep 'inet ' | awk '{print $2}' | cut -d/ -f1)

    # Check if connected
    if [ -n "$CURRENT_SSID" ] && [ -n "$CURRENT_BSSID" ]; then
        IS_CONNECTED=1
    else
        IS_CONNECTED=0
    fi
}

# Load previous state
load_previous_state() {
    if [ -f "$STATE_FILE" ]; then
        . "$STATE_FILE"
        PREV_CONNECTED="${PREV_CONNECTED:-0}"
        PREV_SSID="${PREV_SSID:-}"
        PREV_BSSID="${PREV_BSSID:-}"
        PREV_CHANNEL="${PREV_CHANNEL:-}"
        PREV_RSSI="${PREV_RSSI:-}"
        PREV_IP="${PREV_IP:-}"
    else
        PREV_CONNECTED=0
        PREV_SSID=""
        PREV_BSSID=""
        PREV_CHANNEL=""
        PREV_RSSI=""
        PREV_IP=""
    fi
}

# Save current state
save_current_state() {
    cat > "$STATE_FILE" <<EOF
PREV_CONNECTED=$IS_CONNECTED
PREV_SSID="$CURRENT_SSID"
PREV_BSSID="$CURRENT_BSSID"
PREV_CHANNEL="$CURRENT_CHANNEL"
PREV_RSSI="$CURRENT_RSSI"
PREV_IP="$CURRENT_IP"
EOF
}

# Detect and log changes
detect_changes() {
    # Connection state change
    if [ "$IS_CONNECTED" -eq 1 ] && [ "$PREV_CONNECTED" -eq 0 ]; then
        log_msg "CONNECTED: SSID='$CURRENT_SSID', BSSID=$CURRENT_BSSID, Channel=$CURRENT_CHANNEL, RSSI=${CURRENT_RSSI}dBm, IP=$CURRENT_IP" "info"

    elif [ "$IS_CONNECTED" -eq 0 ] && [ "$PREV_CONNECTED" -eq 1 ]; then
        log_msg "DISCONNECTED: Was connected to '$PREV_SSID' (BSSID=$PREV_BSSID, Channel=$PREV_CHANNEL)" "warn"

    elif [ "$IS_CONNECTED" -eq 1 ]; then
        # Already connected, check for changes

        # SSID change (different network)
        if [ "$CURRENT_SSID" != "$PREV_SSID" ]; then
            log_msg "SSID CHANGED: '$PREV_SSID' -> '$CURRENT_SSID'" "info"
        fi

        # BSSID change (different AP, same network)
        if [ "$CURRENT_BSSID" != "$PREV_BSSID" ]; then
            log_msg "AP CHANGED: BSSID $PREV_BSSID -> $CURRENT_BSSID (Channel $PREV_CHANNEL -> $CURRENT_CHANNEL)" "info"

        # Channel change (same AP, different channel)
        elif [ "$CURRENT_CHANNEL" != "$PREV_CHANNEL" ]; then
            log_msg "CHANNEL CHANGED: $PREV_CHANNEL -> $CURRENT_CHANNEL (BSSID=$CURRENT_BSSID)" "info"
        fi

        # IP change
        if [ "$CURRENT_IP" != "$PREV_IP" ]; then
            log_msg "IP CHANGED: $PREV_IP -> $CURRENT_IP" "info"
        fi

        # Significant RSSI change (more than 10 dBm)
        if [ -n "$CURRENT_RSSI" ] && [ -n "$PREV_RSSI" ]; then
            RSSI_DIFF=$((CURRENT_RSSI - PREV_RSSI))
            # Get absolute value
            [ "$RSSI_DIFF" -lt 0 ] && RSSI_DIFF=$((-RSSI_DIFF))

            if [ "$RSSI_DIFF" -gt 10 ]; then
                log_msg "SIGNAL CHANGE: RSSI ${PREV_RSSI}dBm -> ${CURRENT_RSSI}dBm (BSSID=$CURRENT_BSSID)" "info"
            fi
        fi
    fi
}

# Main execution
get_wireless_status
load_previous_state
detect_changes
save_current_state

# If DEBUG flag is set, output current status
if [ "$DEBUG" = "true" ]; then
    if [ "$IS_CONNECTED" -eq 1 ]; then
        log_msg "Status: Connected to '$CURRENT_SSID' (BSSID=$CURRENT_BSSID, Ch=$CURRENT_CHANNEL, RSSI=${CURRENT_RSSI}dBm, IP=$CURRENT_IP)" "debug"
    else
        log_msg "Status: Not connected" "debug"
    fi
fi
