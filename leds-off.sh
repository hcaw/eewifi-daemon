#!/bin/sh
#
# Turn off all controllable LEDs on the R7000 (Broadcom BCM4360).
# Called at boot via script_init, and can be run manually any time.
#
for l in wlan diag white dmz aoss bridge usb usb3 5g; do
    led "$l" off
done
