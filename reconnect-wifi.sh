#!/bin/sh
#
# Manual WiFi Reconnection Script for FreshTomato
# Use this instead of rebooting when connection is lost
#
# Usage:
#   /jffs/reconnect-wifi.sh          # Try all methods
#   /jffs/reconnect-wifi.sh quick    # Just restart daemon
#   /jffs/reconnect-wifi.sh radio    # Restart radio only
#   /jffs/reconnect-wifi.sh wan      # Restart full WAN
#

LOGGER="/usr/bin/logger"
LOG_TAG="wifi-reconnect"

log_msg() {
    msg="$1"
    echo "$msg"
    if [ -x "$LOGGER" ]; then
        "$LOGGER" -t "$LOG_TAG" -p "daemon.info" "$msg"
    fi
}

# Method 1: Restart daemon only (least disruptive)
restart_daemon() {
    log_msg "Method 1: Restarting eewifi-daemon..."
    /jffs/eewifi-service.sh restart
    sleep 3
    if /jffs/eewifi-service.sh status | grep -q "RUNNING"; then
        log_msg "✓ Daemon restarted successfully"
        return 0
    else
        log_msg "✗ Daemon restart failed"
        return 1
    fi
}

# Method 2: Force wireless reassociation (moderate)
reassociate_wireless() {
    log_msg "Method 2: Forcing wireless reassociation..."

    # Get current SSID to reconnect to
    SSID=$(wl -i eth1 status 2>/dev/null | sed -n 's/^SSID: *"\(.*\)"/\1/p')

    if [ -z "$SSID" ]; then
        log_msg "Warning: Not currently connected to any SSID"
        SSID="EE WiFi"
    fi

    log_msg "Disconnecting from '$SSID'..."
    wl -i eth1 disassoc
    sleep 2

    log_msg "Scanning for '$SSID'..."
    wl -i eth1 scan
    sleep 3

    log_msg "Checking if reconnected..."
    NEW_SSID=$(wl -i eth1 status 2>/dev/null | sed -n 's/^SSID: *"\(.*\)"/\1/p')

    if [ "$NEW_SSID" = "EE WiFi" ]; then
        log_msg "✓ Successfully reconnected to '$NEW_SSID'"
        return 0
    else
        log_msg "✗ Reconnection failed (current SSID: ${NEW_SSID:-none})"
        return 1
    fi
}

# Method 3: Restart wireless interface (more disruptive)
restart_wireless() {
    log_msg "Method 3: Restarting wireless interface (eth1)..."

    # Save current settings
    SSID=$(wl -i eth1 status 2>/dev/null | sed -n 's/^SSID: *"\(.*\)"/\1/p')

    # Disable and re-enable wireless
    log_msg "Bringing down eth1..."
    ifconfig eth1 down
    sleep 2

    log_msg "Bringing up eth1..."
    ifconfig eth1 up
    sleep 3

    # Trigger radio join to reconnect
    log_msg "Triggering radio join..."
    radio join
    sleep 5

    NEW_SSID=$(wl -i eth1 status 2>/dev/null | sed -n 's/^SSID: *"\(.*\)"/\1/p')

    if [ "$NEW_SSID" = "EE WiFi" ]; then
        log_msg "✓ Wireless interface restarted, connected to '$NEW_SSID'"
        return 0
    else
        log_msg "✗ Wireless restart failed (current SSID: ${NEW_SSID:-none})"
        return 1
    fi
}

# Method 4: Renew DHCP (for IP issues)
renew_dhcp() {
    log_msg "Method 4: Renewing DHCP lease..."

    # Find udhcpc process for eth1
    UDHCPC_PID=$(ps | grep 'udhcpc.*eth1' | grep -v grep | awk '{print $1}')

    if [ -n "$UDHCPC_PID" ]; then
        log_msg "Sending SIGUSR1 to udhcpc (PID: $UDHCPC_PID) to renew lease..."
        kill -USR1 "$UDHCPC_PID"
        sleep 3

        IP=$(ifconfig eth1 | grep 'inet addr' | awk '{print $2}' | cut -d: -f2)
        if [ -z "$IP" ]; then
            IP=$(ip addr show eth1 | grep 'inet ' | awk '{print $2}' | cut -d/ -f1)
        fi

        if [ -n "$IP" ]; then
            log_msg "✓ DHCP renewed, IP: $IP"
            return 0
        else
            log_msg "✗ DHCP renewal failed, no IP address"
            return 1
        fi
    else
        log_msg "✗ udhcpc not running for eth1"
        return 1
    fi
}

# Method 5: Full WAN restart (most disruptive, like mwan watchdog would do)
restart_wan() {
    log_msg "Method 5: Restarting WAN service (most disruptive)..."
    log_msg "This will disconnect all clients briefly!"

    service wan restart
    sleep 10

    SSID=$(wl -i eth1 status 2>/dev/null | sed -n 's/^SSID: *"\(.*\)"/\1/p')

    if [ "$SSID" = "EE WiFi" ]; then
        log_msg "✓ WAN restarted, connected to '$SSID'"
        return 0
    else
        log_msg "✗ WAN restart failed (current SSID: ${SSID:-none})"
        return 1
    fi
}

# Show current status
show_status() {
    echo "=== Current Wireless Status ==="
    wl -i eth1 status | head -5
    echo ""
    echo "=== IP Address ==="
    ifconfig eth1 | grep 'inet addr' || ip addr show eth1 | grep 'inet '
    echo ""
    echo "=== Daemon Status ==="
    /jffs/eewifi-service.sh daemon
    echo ""
    echo "=== Portal Login Status ==="
    /jffs/eewifi-service.sh status
}

# Main logic
case "${1:-all}" in
    quick)
        log_msg "=== Quick reconnect: daemon restart only ==="
        restart_daemon
        ;;
    radio)
        log_msg "=== Radio reconnect: reassociate only ==="
        reassociate_wireless
        ;;
    wan)
        log_msg "=== Full WAN restart ==="
        restart_wan
        ;;
    dhcp)
        log_msg "=== DHCP renewal only ==="
        renew_dhcp
        ;;
    status)
        show_status
        ;;
    all|*)
        log_msg "=== Attempting automatic reconnection (all methods) ==="
        log_msg ""

        # Show current state
        show_status
        echo ""

        # Try methods in order of least to most disruptive
        if restart_daemon; then
            log_msg ""
            log_msg "✓✓✓ Reconnected successfully (daemon restart)"
            exit 0
        fi

        sleep 2

        if reassociate_wireless; then
            restart_daemon
            log_msg ""
            log_msg "✓✓✓ Reconnected successfully (wireless reassociation)"
            exit 0
        fi

        sleep 2

        if renew_dhcp; then
            restart_daemon
            log_msg ""
            log_msg "✓✓✓ Reconnected successfully (DHCP renewal)"
            exit 0
        fi

        sleep 2

        if restart_wireless; then
            renew_dhcp
            restart_daemon
            log_msg ""
            log_msg "✓✓✓ Reconnected successfully (wireless interface restart)"
            exit 0
        fi

        sleep 5

        if restart_wan; then
            restart_daemon
            log_msg ""
            log_msg "✓✓✓ Reconnected successfully (WAN restart)"
            exit 0
        fi

        log_msg ""
        log_msg "✗✗✗ All reconnection methods failed - reboot may be required"
        log_msg "Current status:"
        show_status
        exit 1
        ;;
esac
