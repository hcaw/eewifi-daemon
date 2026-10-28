#!/bin/sh
#
# Internet Connectivity Monitor for FreshTomato
# Monitors sustained internet connectivity loss and alerts only on prolonged outages
#
# Usage:
#   Run via cron: */1 * * * * /jffs/internet-monitor.sh
#   Or manually: /jffs/internet-monitor.sh
#
# Configuration:
#   FAILURE_THRESHOLD - Number of consecutive failures before alerting (default: 3)
#   CHECK_INTERVAL - Seconds between checks when run continuously (default: 60)
#   MODE - 'cron' or 'daemon' (default: cron)
#

STATE_FILE="/var/run/internet-monitor.state"
LOGGER="/usr/bin/logger"
LOG_TAG="internet-monitor"

# Configuration
FAILURE_THRESHOLD="${FAILURE_THRESHOLD:-3}"  # Alert after 3 consecutive failures (3 minutes)
CHECK_INTERVAL="${CHECK_INTERVAL:-60}"       # Check every 60 seconds in daemon mode
MODE="${MODE:-cron}"                         # Default to cron mode

# Test targets
PING_TARGET="8.8.8.8"                        # Google DNS
DNS_TEST_DOMAIN="google.com"                 # Domain for DNS resolution test

log_msg() {
    msg="$1"
    priority="${2:-info}"
    if [ -x "$LOGGER" ]; then
        "$LOGGER" -t "$LOG_TAG" -p "daemon.$priority" "$msg"
    fi
}

# Read state from previous run
read_state() {
    if [ -f "$STATE_FILE" ]; then
        . "$STATE_FILE"
    else
        CONSECUTIVE_FAILURES=0
        LAST_STATE="unknown"
        LAST_DOWN_TIME=""
    fi
}

# Save state for next run
write_state() {
    cat > "$STATE_FILE" <<EOF
CONSECUTIVE_FAILURES=$CONSECUTIVE_FAILURES
LAST_STATE=$LAST_STATE
LAST_DOWN_TIME=$LAST_DOWN_TIME
EOF
}

# Check internet connectivity
# Returns 0 if connected, 1 if down
check_connectivity() {
    # Test 1: Ping Google DNS
    if ping -c 2 -W 2 "$PING_TARGET" >/dev/null 2>&1; then
        return 0
    fi

    # Test 2: Try Cloudflare DNS as backup
    if ping -c 2 -W 2 "1.1.1.1" >/dev/null 2>&1; then
        return 0
    fi

    # Test 3: DNS resolution test
    if which nslookup >/dev/null 2>&1; then
        if nslookup "$DNS_TEST_DOMAIN" >/dev/null 2>&1; then
            return 0
        fi
    fi

    # All tests failed
    return 1
}

# Main monitoring logic
monitor_once() {
    read_state

    if check_connectivity; then
        # Internet is UP
        if [ "$LAST_STATE" = "down" ]; then
            # Just recovered from outage
            local downtime_duration=""
            if [ -n "$LAST_DOWN_TIME" ]; then
                local now=$(date +%s)
                local down_seconds=$((now - LAST_DOWN_TIME))
                local down_minutes=$((down_seconds / 60))
                downtime_duration=" (outage lasted ${down_minutes} minutes)"
            fi

            log_msg "✓ Internet connectivity RESTORED${downtime_duration}" "info"
            CONSECUTIVE_FAILURES=0
            LAST_STATE="up"
            LAST_DOWN_TIME=""
        elif [ "$LAST_STATE" != "up" ]; then
            # First check, connection is good
            CONSECUTIVE_FAILURES=0
            LAST_STATE="up"
            LAST_DOWN_TIME=""
        else
            # Still up, reset failure counter
            CONSECUTIVE_FAILURES=0
        fi
    else
        # Internet is DOWN
        CONSECUTIVE_FAILURES=$((CONSECUTIVE_FAILURES + 1))

        if [ "$CONSECUTIVE_FAILURES" -eq "$FAILURE_THRESHOLD" ]; then
            # Just crossed threshold - alert for the first time
            LAST_DOWN_TIME=$(date +%s)
            log_msg "✗ Internet connectivity LOST (${FAILURE_THRESHOLD} consecutive failures detected)" "warn"
            LAST_STATE="down"
        elif [ "$CONSECUTIVE_FAILURES" -gt "$FAILURE_THRESHOLD" ]; then
            # Still down, but already alerted
            if [ "$LAST_STATE" != "down" ]; then
                LAST_STATE="down"
                LAST_DOWN_TIME=$(date +%s)
            fi
        else
            # Failure detected but below threshold - don't alert yet
            # This filters out brief dropouts
            :
        fi
    fi

    write_state
}

# Daemon mode - run continuously
run_daemon() {
    log_msg "Internet monitor started in daemon mode (check every ${CHECK_INTERVAL}s, alert after ${FAILURE_THRESHOLD} failures)" "info"

    while true; do
        monitor_once
        sleep "$CHECK_INTERVAL"
    done
}

# Main entry point
case "$MODE" in
    daemon)
        run_daemon
        ;;
    cron|*)
        # Single check for cron mode
        monitor_once
        ;;
esac
