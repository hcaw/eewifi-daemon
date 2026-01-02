# EE WiFi Daemon - Project Context

## Overview

This is an auto-login daemon for EE WiFi (formerly BT Wi-Fi) captive portals, designed to run on embedded Linux routers. It automatically authenticates when connected to an "EE WiFi" SSID.

## Target Environment

- **Router**: Netgear R7000 running FreshTomato 2025.4 K26ARM
- **Shell**: BusyBox ash (not bash)
- **Persistent storage**: `/jffs/` (survives reboots)
- **Config location**: `/jffs/eewifi-daemon.config`

## BusyBox Limitations

The router uses BusyBox which has limited implementations of common tools:

### wget
- Does **not** support `--no-cache`
- Use `-T SEC` instead of `--timeout=SEC`
- May fail with "too many redirections" on POST requests but the request still succeeds
- Available options: `-c`, `-q`, `-S`, `-O`, `-o`, `-P`, `-U`, `-T`, `-Y`, `--spider`, `--header`, `--post-data`, `--post-file`, `--no-check-certificate`

### Shell
- Use `.` instead of `source` for sourcing files
- Use `[ ]` instead of `[[ ]]` for conditionals
- Use `"$var" -eq 1` instead of `$var == 1`
- Use `which cmd` instead of `command -v cmd` (command builtin not available)
- No `logread` command available

## SSID Detection

The router doesn't have `iwgetid`, `iwinfo`, or `iwconfig`. Use the Broadcom `wl` utility instead:

```sh
wl -i eth1 status   # 2.4GHz interface
wl -i eth2 status   # 5GHz interface (if available)
```

Output format:
```
SSID: "EE WiFi"
Mode: Managed   RSSI: -59 dBm   ...
```

## EE WiFi Login API

### Check login status
```
GET https://ee-wifi.ee.co.uk/home
```
- If logged in: Response contains "You are now connected"
- If not logged in: Response shows login form

### Login (EE WiFi Voucher/Pay & Go accounts)
```
POST https://ee-wifi.ee.co.uk/ante
Content-Type: application/x-www-form-urlencoded

inputUsername=email@example.com&username=wam/email@example.com&password=PASSWORD&xhtmlLogon=https://ee-wifi.ee.co.uk/ante
```

### Logout
```
GET https://ee-wifi.ee.co.uk/accountLogoff/home?confirmed=true
```

## Network Topology

When connected to EE WiFi:
- Router WAN IP: CGNAT address (100.x.x.x/16)
- Captive portal gateway: 192.168.23.21:8443 (not always reachable)
- Actual login server: ee-wifi.ee.co.uk (109.144.192.50)

## Testing on Router

```sh
# SSH to router
ssh root@192.168.1.1

# Check wireless status
wl -i eth1 status

# Test login manually
wget -qO - --no-check-certificate "https://ee-wifi.ee.co.uk/home" | grep -c "You are now connected"

# Run daemon with debug
DEBUG=true /jffs/eewifi-daemon.sh
```

## Startup Configuration

Add to FreshTomato web UI under Administration > Scripts > Init or WAN Up:
```sh
/jffs/eewifi-daemon.sh &
```

Or add to `/etc/rc.local` (if available).

## Common Issues

1. **"too many redirections"**: BusyBox wget limitation - login still works, verify by checking status page after POST
2. **SSID not detected**: Use `wl` utility, not `iwinfo`/`iwconfig`
3. **Config not found**: Check path is `/jffs/eewifi-daemon.config` and file exists after reboot
4. **Script syntax errors**: Ensure POSIX sh compatibility (no bashisms)

---

## Router Reconnaissance (2 Jan 2026)

### Current System State

**Hardware/Firmware:**
- Netgear R7000, FreshTomato 2025.4 K26ARM USB AIO-64K
- Kernel: Linux 2.6.36.4brcmarm (armv7l)
- Memory: 256MB total, ~11% used
- BusyBox v1.37.0

**Network Configuration:**
- WAN IP: CGNAT address (100.x.x.x/16 from EE WiFi hotspot)
- LAN: 192.168.1.1/24, DHCP range 192.168.1.2-50
- WL0 (eth1): 2.4GHz, connected to "EE WiFi" as wireless WAN client
- WL1 (eth2): 5GHz, broadcasting "FreshTomato50" as local AP

**Services Running:**
- dropbear (SSH on port 22)
- httpd (web UI)
- dnsmasq (DNS/DHCP)
- crond (cron daemon)
- telnetd
- udhcpc (DHCP client for WAN)
- ntpd (time sync)

### Files in /jffs/

| File | Size | Description |
|------|------|-------------|
| `eewifi-daemon.sh` | 3870 bytes | Main daemon script (has bashisms - needs sync) |
| `eewifi-daemon.config` | 771 bytes | Config with credentials |
| `ee_wifi_login.sh` | 3902 bytes | Older login script |
| `ee_wifi_service.sh` | 2095 bytes | Older service script |
| `uplink_status.sh` | 7712 bytes | Uplink status checker |

### Script Version Mismatch

**Issue:** The script on the router (`/jffs/eewifi-daemon.sh`) contains bashisms that fail on BusyBox ash:
- Uses `source` instead of `.`
- Uses `--no-cache` (not supported by BusyBox wget)
- Uses `--timeout=SEC` instead of `-T SEC`
- Uses `[[ ]]` instead of `[ ]`

**Solution:** The local repo version is fixed. Need to upload to router.

### Automatic Startup - NOT CONFIGURED

The daemon is **not** running automatically. Analysis of logs shows:
- No evidence of eewifi-daemon.sh being executed at boot
- No init scripts, wanup hooks, or rc.local entries for the daemon
- Cron is running but only has MARK logging jobs

**To enable automatic startup**, add to FreshTomato Web UI:
- Administration → Scripts → Init: `sleep 30 && /jffs/eewifi-daemon.sh &`
- Or Administration → Scripts → WAN Up: `/jffs/eewifi-daemon.sh &`

### Manual Login Test Commands

```sh
# Check if connected to EE WiFi
wl -i eth1 status | grep SSID

# Check if logged in
wget -qO - --no-check-certificate "https://ee-wifi.ee.co.uk/home" | grep -c "You are now connected"

# Manual login (replace EMAIL and PASSWORD)
wget -qO - --no-check-certificate --post-data "inputUsername=EMAIL&username=wam/EMAIL&password=PASSWORD&xhtmlLogon=https://ee-wifi.ee.co.uk/ante" "https://ee-wifi.ee.co.uk/ante"
```

### SSH Access

- Default credentials: `root` / `admin`
- SSH may intermittently be blocked by firewall rules (observed DROP logs on br0→port 22)
- If SSH times out, use web UI or try again later

### Observed Traffic

The logs show significant dropped packets from 217.39.0.50:8099 → router on various ports. This appears to be EE/BT infrastructure traffic being dropped by the firewall (likely connection tracking issues or unsolicited traffic).
