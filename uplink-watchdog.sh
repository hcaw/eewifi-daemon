#!/bin/sh
#
# Uplink Watchdog for FreshTomato
# Detects loss of the wireless WAN uplink (eth1) and triggers reconnect-wifi.sh
#
# Run via cron every minute:
#   cru a uplink-watchdog "*/1 * * * * /jffs/uplink-watchdog.sh"
#

STATE_FILE="/var/run/uplink-watchdog.state"
LOGGER="/usr/bin/logger"
LOG_TAG="uplink-watchdog"

FAILURE_THRESHOLD="${FAILURE_THRESHOLD:-2}"   # consecutive failed checks before acting
COOLDOWN_SECONDS="${COOLDOWN_SECONDS:-180}"   # minimum time between reconnect attempts

log_msg() {
    msg="$1"
    priority="${2:-info}"
    [ -x "$LOGGER" ] && "$LOGGER" -t "$LOG_TAG" -p "daemon.$priority" "$msg"
}

check_uplink() {
    ping -c 2 -W 2 -I eth1 1.1.1.1 >/dev/null 2>&1 && return 0
    ping -c 2 -W 2 -I eth1 8.8.8.8 >/dev/null 2>&1 && return 0
    return 1
}

read_state() {
    [ -f "$STATE_FILE" ] && . "$STATE_FILE"
    CONSECUTIVE_FAILURES="${CONSECUTIVE_FAILURES:-0}"
    LAST_ATTEMPT="${LAST_ATTEMPT:-0}"
}

write_state() {
    cat > "$STATE_FILE" <<EOF
CONSECUTIVE_FAILURES=$CONSECUTIVE_FAILURES
LAST_ATTEMPT=$LAST_ATTEMPT
EOF
}

read_state

if check_uplink; then
    [ "$CONSECUTIVE_FAILURES" -gt 0 ] && log_msg "Uplink recovered after $CONSECUTIVE_FAILURES failed check(s)" "info"
    CONSECUTIVE_FAILURES=0
    write_state
    exit 0
fi

CONSECUTIVE_FAILURES=$((CONSECUTIVE_FAILURES + 1))
write_state

if [ "$CONSECUTIVE_FAILURES" -lt "$FAILURE_THRESHOLD" ]; then
    log_msg "Uplink check failed ($CONSECUTIVE_FAILURES/$FAILURE_THRESHOLD) - waiting to confirm" "warn"
    exit 0
fi

NOW=$(date +%s)
SINCE_LAST=$((NOW - LAST_ATTEMPT))

if [ "$LAST_ATTEMPT" -ne 0 ] && [ "$SINCE_LAST" -lt "$COOLDOWN_SECONDS" ]; then
    log_msg "Uplink still down, but last reconnect attempt was ${SINCE_LAST}s ago - within cooldown, skipping" "warn"
    exit 0
fi

log_msg "Uplink down for $CONSECUTIVE_FAILURES consecutive checks - triggering reconnect" "err"
LAST_ATTEMPT=$NOW
write_state

/jffs/reconnect-wifi.sh all >/tmp/reconnect-wifi.last.log 2>&1

if check_uplink; then
    log_msg "Reconnect succeeded" "info"
    CONSECUTIVE_FAILURES=0
    write_state
else
    log_msg "Reconnect attempt did not restore connectivity - will retry after cooldown" "err"
fi
