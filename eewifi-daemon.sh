#!/bin/sh
# Copyright 2025 Adrian Robinson
# Updated to support latest EE WiFi Login, and OpenWRT 22.03
#
# add this to the bottom of /etc/rc.local:
# /path/to/wifi-daemon.sh &

# location of the config file (include absolute path)
CONFIG_FILE="/jffs/eewifi-daemon.config"

# static options (BusyBox wget doesn't support --no-cache)
WGET="wget -qO - --no-check-certificate"

# Logger configuration
LOGGER="/usr/bin/logger"
LOG_TAG="eewifi-daemon"

# Logging function - sends to syslog with proper tagging
# Usage: log_msg "message" [priority]
# Priority: info (default), warn, err, debug
log_msg() {
    msg="$1"
    priority="${2:-info}"

    # Always log errors and warnings
    # For info and debug, respect DEBUG flag
    case "$priority" in
        err|warn)
            if [ -x "$LOGGER" ]; then
                "$LOGGER" -t "$LOG_TAG" -p "daemon.$priority" "$msg"
            fi
            ;;
        debug)
            if [ "$DEBUG" = 'true' ] && [ -x "$LOGGER" ]; then
                "$LOGGER" -t "$LOG_TAG" -p "daemon.debug" "$msg"
            fi
            ;;
        info|*)
            if [ -x "$LOGGER" ]; then
                "$LOGGER" -t "$LOG_TAG" -p "daemon.info" "$msg"
            fi
            ;;
    esac
}

# load external config file for login details
if [ -e "$CONFIG_FILE" ]; then
    . "$CONFIG_FILE"
    log_msg "Daemon starting, config loaded from $CONFIG_FILE" "info"
else
    # Try to log error, but logger may not be available yet
    if [ -x "$LOGGER" ]; then
        "$LOGGER" -t "$LOG_TAG" -p "daemon.err" "Config file '$CONFIG_FILE' not found, exiting"
    fi
    exit 1
fi

check_tool() {
    command_name=$1
    if ! which "$command_name" >/dev/null 2>&1; then
        log_msg "Required command '$command_name' not found" "err"
        exit 1
    fi
}

# fetch_url: wrapper that prefers curl then wget. Usage:
# fetch_url <url> [postdata]
# Note: BusyBox wget may report "too many redirections" on POST requests
# but the login still succeeds - we handle this by checking the result separately
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
            # BusyBox wget may fail with "too many redirections" but login still works
            wget -qO - --no-check-certificate -T "$timeout" --post-data "$postdata" "$url" 2>/dev/null
        else
            wget -qO - --no-check-certificate -T "$timeout" "$url" 2>/dev/null
        fi
    fi
}

# get_ssid: tries several methods to determine current SSID for $INTERFACE
# On FreshTomato/Broadcom routers, the 'wl' utility is the reliable method
get_ssid() {
    # try Broadcom 'wl' utility first (FreshTomato/Netgear) - most reliable on these routers
    if which wl >/dev/null 2>&1; then
        # Try common wireless interfaces: eth1 (2.4GHz), eth2 (5GHz)
        for iface in eth1 eth2 wl0 wl1; do
            ssid=$(wl -i "$iface" status 2>/dev/null | sed -n 's/^SSID: *"\(.*\)"/\1/p')
            if [ -n "$ssid" ]; then printf "%s" "$ssid"; return 0; fi
            # Also try without quotes (some versions output differently)
            ssid=$(wl -i "$iface" status 2>/dev/null | sed -n 's/^SSID: *//p' | head -n1 | tr -d '"')
            if [ -n "$ssid" ]; then printf "%s" "$ssid"; return 0; fi
        done
    fi

    # try iwgetid
    if which iwgetid >/dev/null 2>&1; then
        ssid=$(iwgetid -r 2>/dev/null)
        if [ -n "$ssid" ]; then printf "%s" "$ssid"; return 0; fi
    fi

    # try iwinfo
    if which iwinfo >/dev/null 2>&1; then
        ssid=$(iwinfo "$INTERFACE" info 2>/dev/null | awk -F: '/SSID|ESSID/ {gsub(/^[ \\t]+|[ \\t]+$/,"",$2); print $2; exit}')
        if [ -n "$ssid" ]; then printf "%s" "$ssid"; return 0; fi
    fi

    # try iwconfig
    if which iwconfig >/dev/null 2>&1; then
        ssid=$(iwconfig "$INTERFACE" 2>/dev/null | sed -n 's/.*ESSID:"\([^"]*\)".*/\1/p')
        if [ -n "$ssid" ]; then printf "%s" "$ssid"; return 0; fi
    fi

    return 1
}

# get_connection_info: Get detailed connection information (BSSID, channel, RSSI)
# Sets global variables: CONN_BSSID, CONN_CHANNEL, CONN_RSSI
get_connection_info() {
    CONN_BSSID=""
    CONN_CHANNEL=""
    CONN_RSSI=""

    if which wl >/dev/null 2>&1; then
        for iface in eth1 eth2 wl0 wl1; do
            # Check if interface has an SSID (is connected)
            local test_ssid=$(wl -i "$iface" status 2>/dev/null | sed -n 's/^SSID: *"\(.*\)"/\1/p')
            [ -z "$test_ssid" ] && continue

            # Get BSSID
            CONN_BSSID=$(wl -i "$iface" bssid 2>/dev/null | awk '{print $NF}')

            # Get channel from status output
            CONN_CHANNEL=$(wl -i "$iface" status 2>/dev/null | sed -n 's/.*Channel: *\([0-9]*\).*/\1/p')

            # Get RSSI
            CONN_RSSI=$(wl -i "$iface" rssi 2>/dev/null | tr -d ' ')

            # If we got info, return success
            if [ -n "$CONN_BSSID" ]; then
                return 0
            fi
        done
    fi

    return 1
}

# Connection state tracking variables
PREV_SSID=""
PREV_BSSID=""
PREV_CHANNEL=""
WAS_CONNECTED=false

while true; do
        ssid=$(get_ssid 2>/dev/null)

        # Track connection state changes
        if [ "$ssid" = "EE WiFi" ]; then
            # Get detailed connection info
            get_connection_info

            # Check if this is a new connection or reconnection
            if [ "$WAS_CONNECTED" = false ]; then
                log_msg "Connected to 'EE WiFi' SSID (BSSID: ${CONN_BSSID}, Channel: ${CONN_CHANNEL}, RSSI: ${CONN_RSSI} dBm)" "info"
                WAS_CONNECTED=true
            elif [ -n "$PREV_BSSID" ] && [ "$CONN_BSSID" != "$PREV_BSSID" ]; then
                log_msg "AP changed: BSSID ${PREV_BSSID} -> ${CONN_BSSID}" "info"
            elif [ -n "$PREV_CHANNEL" ] && [ "$CONN_CHANNEL" != "$PREV_CHANNEL" ]; then
                log_msg "Channel changed: ${PREV_CHANNEL} -> ${CONN_CHANNEL} (BSSID: ${CONN_BSSID})" "info"
            fi

            # Update tracking variables
            PREV_SSID="$ssid"
            PREV_BSSID="$CONN_BSSID"
            PREV_CHANNEL="$CONN_CHANNEL"

        fi

        if [ "$ssid" = "EE WiFi" ]; then
            log_msg "Connected to 'EE WiFi' access point, checking login status" "debug"
            serverResponse=$(fetch_url "$SERVER/home")
            isLoggedIn=$(printf "%s" "$serverResponse" | grep -c "You are now connected")
        if [ "$isLoggedIn" -ge 1 ]; then
                log_msg "Already logged in to EE WiFi" "debug"
                log_msg "Sleeping for ${DELAY_SUCCESS}s before next check" "debug"
                sleep "$DELAY_SUCCESS"
        else
                log_msg "Not logged in to EE WiFi, attempting authentication" "info"
                postdata="inputUsername=$USERNAME&username=wam/$USERNAME&password=$PASSWORD&xhtmlLogon=$SERVER/ante"
                # Send login POST - may fail with redirect error but login still succeeds
                fetch_url "$SERVER/ante" "$postdata" >/dev/null 2>&1
                # Brief pause then verify login by checking status page
                sleep 2
                serverResponse=$(fetch_url "$SERVER/home")
                isAuthenticated=$(printf "%s" "$serverResponse" | grep -c "You are now connected")
            if [ "$isAuthenticated" -ge 1 ]; then
                    log_msg "Authentication to EE WiFi successful for user $USERNAME" "info"
                    log_msg "Sleeping for ${DELAY_SUCCESS}s before next check" "debug"
                    sleep "$DELAY_SUCCESS"
            else
                    log_msg "Authentication to EE WiFi failed for user $USERNAME" "warn"
                    log_msg "Retrying in ${DELAY_LOGIN_ATTEMPTS}s" "debug"
                    sleep "$DELAY_LOGIN_ATTEMPTS"
            fi
        fi
    else
            # Handle disconnection
            if [ "$WAS_CONNECTED" = true ]; then
                log_msg "Disconnected from 'EE WiFi' (last BSSID: ${PREV_BSSID}, Channel: ${PREV_CHANNEL})" "warn"
                WAS_CONNECTED=false
            fi

            log_msg "Not connected to 'EE WiFi' access point (current SSID: ${ssid:-none}), waiting" "debug"
            log_msg "Sleeping for ${DELAY_INTERFACE}s before rechecking SSID" "debug"
            sleep "$DELAY_INTERFACE"
    fi
done