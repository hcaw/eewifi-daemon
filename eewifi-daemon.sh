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

# load external config file for login details
if [ -e "$CONFIG_FILE" ]; then
    . "$CONFIG_FILE"
else
    echo "Error, config file '${CONFIG_FILE}' could not be found!"
    exit 1
fi

check_tool() {
    command_name=$1
    if ! which "$command_name" >/dev/null 2>&1; then
        printf "Error, command '%s' could not be found!\n" "$command_name" >&2
        exit 1
    fi
}
# Ensure at least basic tools are present; some have fallbacks below
# check_tool logger

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

while true; do
        ssid=$(get_ssid 2>/dev/null)
        if [ "$ssid" = "EE WiFi" ]; then
            if [ "$DEBUG" = 'true' ]; then printf "Info: You're connected to 'EE WiFi' access point\n"; fi
            serverResponse=$(fetch_url "$SERVER/home")
            isLoggedIn=$(printf "%s" "$serverResponse" | grep -c "You are now connected")
        if [ "$isLoggedIn" -ge 1 ]; then
                if [ "$DEBUG" = 'true' ]; then printf "Info: You're logged in to EE WiFi!\n"; fi
                if [ "$DEBUG" = 'true' ]; then printf "Info: Sleeping for %s seconds...\n" "$DELAY_SUCCESS"; fi
                sleep "$DELAY_SUCCESS"
        else
                if [ "$DEBUG" = 'true' ]; then printf "Info: You're not logged in to EE WiFi\n"; fi
                if [ "$DEBUG" = 'true' ]; then printf "Info: Attempting login\n"; fi
                postdata="inputUsername=$USERNAME&username=wam/$USERNAME&password=$PASSWORD&xhtmlLogon=$SERVER/ante"
                # Send login POST - may fail with redirect error but login still succeeds
                fetch_url "$SERVER/ante" "$postdata" >/dev/null 2>&1
                # Brief pause then verify login by checking status page
                sleep 2
                serverResponse=$(fetch_url "$SERVER/home")
                isAuthenticated=$(printf "%s" "$serverResponse" | grep -c "You are now connected")
            if [ "$isAuthenticated" -ge 1 ]; then
                    if [ "$DEBUG" = 'true' ]; then printf "Success: Authenticating to EE WiFi was successful!\n"; fi
                    echo "eewifi - Success: Authenticating to EE WiFi was successful"
                    if [ "$DEBUG" = 'true' ]; then printf "Info: Sleeping for %s seconds...\n" "$DELAY_SUCCESS"; fi
                    sleep "$DELAY_SUCCESS"
            else
                    if [ "$DEBUG" = 'true' ]; then printf "Error: Authenticating to EE WiFi was unsuccessful\n"; fi
                    if [ "$DEBUG" = 'true' ]; then printf "Info: Sleeping for %s seconds...\n" "$DELAY_LOGIN_ATTEMPTS"; fi
                    sleep "$DELAY_LOGIN_ATTEMPTS"
            fi
        fi
    else
            if [ "$DEBUG" = 'true' ]; then printf "Error: You're not connected to 'EE WiFi' access point\n"; fi
            if [ "$DEBUG" = 'true' ]; then printf "Info: Sleeping for %s seconds...\n" "$DELAY_INTERFACE"; fi
            sleep "$DELAY_INTERFACE"
    fi
done