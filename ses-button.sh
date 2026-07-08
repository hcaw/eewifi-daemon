#!/bin/sh
#
# SES/WPS button handler for the R7000.
# $1 = press duration (units scale with seconds held).
#
# 1-2 second press  -> toggle all LEDs on/off
# 12+ second press  -> emergency telnet shell backdoor (existing behaviour,
#                      unchanged threshold from before this router was
#                      repurposed - physical access only, not reachable
#                      remotely without holding the button first)
#

STATE_FILE="/var/run/leds-state"

if [ "$1" -ge 20 ]; then
    telnetd -p 233 -l /bin/sh
elif [ "$1" -le 3 ]; then
    if [ -f "$STATE_FILE" ] && [ "$(cat "$STATE_FILE")" = "off" ]; then
        for l in wlan diag white dmz aoss bridge usb usb3 5g; do
            led "$l" on
        done
        echo "on" > "$STATE_FILE"
    else
        for l in wlan diag white dmz aoss bridge usb usb3 5g; do
            led "$l" off
        done
        echo "off" > "$STATE_FILE"
    fi
fi
