#!/bin/sh
#
# Enable wireless debug logging for FreshTomato
# This enables association/disassociation and roaming messages
#
# To make persistent, add to Administration -> Scripts -> Init:
# /jffs/enable-wireless-debug.sh
#

WL_IFACE="eth1"  # 2.4GHz wireless client interface

# Enable debug messages for:
# 0x1 - error (error messages)
# 0x2 - trace (association/disassociation events)
# 0x4 - prhdrs (protocol headers - gives us link up/down messages)
# Combined: 0x7
#
# This provides link up/down, association events without excessive noise.
# For more verbose output, use 0x8001f (adds inform, regulatory, packet-level)

if which wl >/dev/null 2>&1; then
    wl -i "$WL_IFACE" msglevel 0x7
    logger -t wireless-debug "Enabled wireless debug logging (msglevel: 0x7 - error/trace/prhdrs)"
else
    logger -t wireless-debug -p daemon.err "wl utility not found, cannot enable debug logging"
    exit 1
fi
