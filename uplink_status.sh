#!/bin/sh
# FreshTomato R7000 – Wireless Client Upstream Status (one big script)
# ---------------------------------------------------------------
# Prints a comprehensive snapshot of the upstream Wi‑Fi connection when
# the router is in wireless client (STA/WET) mode. Safe to run repeatedly.
#
# Saves you from hunting across nvram, wl, ip, and syslog.
#
# Usage:
#   sh upstream_status.sh
#
# Optional environment toggles:
#   SCAN=1        # also perform a wl scan and show scanresults
#   PINGS=1       # run connectivity pings (GW, 1.1.1.1, 8.8.8.8)
#   DNS_TEST=1    # run a DNS resolution test (nslookup example.com)
#
# Notes:
# - Some wl subcommands vary by build; failures are harmless.
# - BusyBox ash-compatible; avoid Bash-specific features.

set -u

PATH="/usr/sbin:/sbin:/usr/bin:/bin:$PATH"

# ----------------------------
# Helpers
# ----------------------------

havecmd() { which "$1" >/dev/null 2>&1; }

hr() { printf '%s\n' "----------------------------------------------------------------"; }

header() {
  hr
  printf '### %s ###\n' "$1"
  hr
}

kv() { printf '%-20s %s\n' "$1" "$2"; }

try() {
  # Run a command; suppress errors into stderr, but show nothing if it fails.
  # Capture output and print it if non-empty.
  # Usage: try <cmd...>
  if out="$("$@" 2>/dev/null)"; then
    [ -n "$out" ] && printf '%s\n' "$out"
  fi
}

ts() { date +"%Y-%m-%d %H:%M:%S %Z"; }

# ----------------------------
# Discover interfaces (WAN/WLAN mapping)
# ----------------------------

# Read common NVRAM variables (with safe fallbacks)
nv() { nvram get "$1" 2>/dev/null; }

OS_VER="$(nv os_version)"
WL0_IF="$(nv wl0_ifname)"; [ -z "${WL0_IF:-}" ] && WL0_IF="eth1"
WL1_IF="$(nv wl1_ifname)"; [ -z "${WL1_IF:-}" ] && WL1_IF="eth2"

WAN_IF="$(nv wan_iface)"

# Heuristic: if wan_iface is empty or looks like an Ethernet VLAN while in wireless client,
# use the radio whose mode is 'sta' (client) or 'wet' (media bridge).
WL0_MODE="$(nv wl0_mode)"
WL1_MODE="$(nv wl1_mode)"

case "${WL0_MODE:-}" in
  sta|wet) [ -z "${WAN_IF:-}" ] || case "$WAN_IF" in vlan*|ppp*|br*) WAN_IF="$WL0_IF";; esac ;;
esac
case "${WL1_MODE:-}" in
  sta|wet) [ -z "${WAN_IF:-}" ] || case "$WAN_IF" in vlan*|ppp*|br*) WAN_IF="$WL1_IF";; esac ;;
esac

# If still empty, prefer wl1 (5 GHz) then wl0 (2.4 GHz)
[ -z "${WAN_IF:-}" ] && WAN_IF="$WL1_IF"
[ -z "${WAN_IF:-}" ] && WAN_IF="$WL0_IF"

# ----------------------------
# Environment
# ----------------------------
header "Environment"
kv "Timestamp:" "$(ts)"
kv "Kernel:" "$(uname -a 2>/dev/null)"
kv "Firmware:" "${OS_VER:-unknown}"
kv "Router Model:" "$(nvod=$(nvod="$(nv productid)"); [ -n "$nvod" ] && echo "$nvod" || echo "$(nvod="$(nv model)"; [ -n "$nvod" ] && echo "$nvod" || echo unknown)")"
kv "wl tool present:" "$(havecmd wl && echo yes || echo no)"
kv "logread present:" "$(havecmd logread && echo yes || echo no)"

# ----------------------------
# Interface mapping
# ----------------------------
header "Interfaces"
kv "WAN_IF:" "$WAN_IF"
kv "wl0_ifname (2.4 GHz):" "$WL0_IF"
kv "wl1_ifname (5 GHz):" "$WL1_IF"
kv "wan_proto:" "$(nv wan_proto)"
kv "lan_ifname:" "$(nv lan_ifname)"

# ----------------------------
# Wireless driver status (Broadcom wl)
# ----------------------------
header "Wireless Link / Association (wl)"

AP_BSSID=""
AP_SSID=""

if havecmd wl; then
  printf '%s\n' "wl -i $WAN_IF status"
  try wl -i "$WAN_IF" status
  printf '\n%s\n' "wl -i $WAN_IF assoc   (AP BSSID/SSID)"
  try wl -i "$WAN_IF" assoc

  # Extract BSSID
  AP_BSSID="$(wl -i "$WAN_IF" bssid 2>/dev/null | awk '{print $NF}')"
  [ -n "$AP_BSSID" ] && kv "BSSID:" "$AP_BSSID"

  # SSID may be available via wl ssid or parsed from wl assoc
  AP_SSID="$(wl -i "$WAN_IF" ssid 2>/dev/null | sed -e 's/^Current SSID: //')"
  [ -z "$AP_SSID" ] && AP_SSID="$(wl -i "$WAN_IF" assoc 2>/dev/null | awk -F': ' '/SSID/ {print $2}')"
  [ -n "$AP_SSID" ] && kv "SSID:" "$AP_SSID"

  kv "ChannelSpec:" "$(wl -i "$WAN_IF" chanspec 2>/dev/null)"
  kv "Rate (PHY):" "$(wl -i "$WAN_IF" phy_rate 2>/dev/null || wl -i "$WAN_IF" rate 2>/dev/null)"
  kv "Country:" "$(wl -i "$WAN_IF" country 2>/dev/null)"

  kv "RSSI (dBm):" "$(wl -i "$WAN_IF" rssi 2>/dev/null)"
  kv "Noise (dBm):" "$(wl -i "$WAN_IF" noise 2>/dev/null)"

  if [ -n "$AP_BSSID" ]; then
    printf '\n%s "%s"\n' "wl -i $WAN_IF sta_info" "$AP_BSSID"
    try wl -i "$WAN_IF" sta_info "$AP_BSSID"
  fi
else
  printf '%s\n' "wl tool not available on this build."
fi

# ----------------------------
# L2/L3 interface view
# ----------------------------
header "IP / Link State"

if havecmd ip; then
  printf 'ip addr show dev %s\n' "$WAN_IF"
  try ip addr show dev "$WAN_IF"
  printf '\n'
  printf 'ip link show dev %s\n' "$WAN_IF"
  try ip link show dev "$WAN_IF"
else
  printf 'ifconfig %s\n' "$WAN_IF"
  try ifconfig "$WAN_IF"
fi

printf '\nRouting\n'
try ip route
printf '\nDefault route\n'
try ip route show default

GW="$(ip route 2>/dev/null | awk '/default/ {print $3; exit}')"
[ -n "$GW" ] && kv "Default gateway:" "$GW"

kv "WAN IP:" "$(nv wan_ipaddr)"
kv "WAN Netmask:" "$(nv wan_netmask)"
kv "WAN Gateway (nvram):" "$(nv wan_gateway)"
kv "WAN DNS (nvram):" "$(nv wan_dns)"

# ----------------------------
# DHCP lease and WAN state
# ----------------------------
header "WAN / DHCP State (nvram + udhcpc)"

kv "wan_proto:" "$(nv wan_proto)"
kv "wan_status:" "$(nv wan_status)"
kv "wan_lease (s):" "$(nv wan_lease)"
kv "wan_lease_remain (s):" "$(nv wan_lease_remain)"

printf '\nLease artefacts (udhcpc)\n'
ls -l /tmp/udhcpc 2>/dev/null
ls -l /var/lib/misc 2>/dev/null

printf '\nudhcpc in logs\n'
if havecmd logread; then
  try logread | grep -i udhcpc
else
  try dmesg | grep -i udhcpc
fi

# ----------------------------
# Wireless/system event logs
# ----------------------------
header "Recent Wireless / WAN Events"

LOG_GREP='wlceventd|nas|wpa|udhcpc|dhcp|deauth|auth|assoc|roam|disassoc'
if havecmd logread; then
  logread | grep -E -i "$LOG_GREP" | tail -n 200
else
  dmesg | grep -E -i "$LOG_GREP" | tail -n 200
fi

# ----------------------------
# Connectivity checks
# ----------------------------
if [ "${PINGS:-0}" = "1" ]; then
  header "Connectivity Checks (ping)"
  if [ -n "$GW" ]; then
    printf 'Ping default gateway (%s)\n' "$GW"
    ping -c3 -W2 "$GW" 2>/dev/null || true
    printf '\n'
  fi
  printf 'Ping 1.1.1.1\n'
  ping -c3 -W2 1.1.1.1 2>/dev/null || true
  printf '\nPing 8.8.8.8\n'
  ping -c3 -W2 8.8.8.8 2>/dev/null || true
fi

if [ "${DNS_TEST:-0}" = "1" ]; then
  header "DNS Resolution Test"
  if havecmd nslookup; then
    nslookup example.com 2>/dev/null || true
  else
    printf '%s\n' "nslookup not present on this build."
  fi
fi

# ----------------------------
# Optional scan/survey
# ----------------------------
if [ "${SCAN:-0}" = "1" ]; then
  header "Scan / Survey (wl)"
  if havecmd wl; then
    printf '%s\n' "wl -i $WAN_IF scan"
    wl -i "$WAN_IF" scan 2>/dev/null || true
    sleep 3
    printf '\n%s\n' "wl -i $WAN_IF scanresults"
    wl -i "$WAN_IF" scanresults 2>/dev/null || true
  else
    printf '%s\n' "wl tool not available for scanning."
  fi
fi

# ----------------------------
# Summary snapshot
# ----------------------------
header "Compact Summary"

kv "WAN_IF:" "$WAN_IF"
kv "SSID:" "${AP_SSID:-unknown}"
kv "BSSID:" "${AP_BSSID:-unknown}"
kv "Chanspec:" "$(wl -i "$WAN_IF" chanspec 2>/dev/null)"
kv "Rate (PHY):" "$(wl -i "$WAN_IF" phy_rate 2>/dev/null || wl -i "$WAN_IF" rate 2>/dev/null)"
kv "RSSI (dBm):" "$(wl -i "$WAN_IF" rssi 2>/dev/null)"
kv "Noise (dBm):" "$(wl -i "$WAN_IF" noise 2>/dev/null)"
kv "WAN IP:" "$(nv wan_ipaddr)"
kv "Default GW:" "${GW:-unknown}"
kv "DNS (nvram):" "$(nv wan_dns)"

hr
printf '%s\n' "End of upstream status."
hr

