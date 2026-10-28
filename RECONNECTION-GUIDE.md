## Manual Reconnection Guide

**Instead of rebooting the router**, use these commands to recover from WiFi disconnections.

### Quick Reference

```bash
# SSH to router
ssh root@192.168.1.1

# Automatic recovery (tries all methods)
/jffs/reconnect-wifi.sh

# Quick methods (try first)
/jffs/reconnect-wifi.sh quick    # Just restart daemon
/jffs/reconnect-wifi.sh radio    # Force reassociation
/jffs/reconnect-wifi.sh dhcp     # Renew IP address

# Nuclear option (if above fail)
/jffs/reconnect-wifi.sh wan      # Full WAN restart (disconnects all clients)

# Check status
/jffs/reconnect-wifi.sh status
```

### Recovery Methods (in order of severity)

#### 1. Restart Daemon (Least Disruptive - 3 seconds)
```bash
/jffs/eewifi-service.sh restart
```
**Use when:** Portal authentication seems stuck, daemon not responding.
**Effect:** Restarts login daemon only, wireless stays connected.

#### 2. Force Wireless Reassociation (Moderate - 5 seconds)
```bash
/jffs/reconnect-wifi.sh radio
```
**Use when:** Connected to SSID but no internet access.
**Effect:** Disconnects and rescans for "EE WiFi", reconnects.

#### 3. Renew DHCP (Moderate - 3 seconds)
```bash
/jffs/reconnect-wifi.sh dhcp
```
**Use when:** Connected but wrong/no IP address.
**Effect:** Requests new IP from DHCP server.

#### 4. Restart Wireless Interface (Disruptive - 10 seconds)
```bash
ifconfig eth1 down && sleep 2 && ifconfig eth1 up && radio join
```
**Use when:** Wireless driver seems stuck.
**Effect:** Brings interface down/up, triggers radio join process.

#### 5. Full WAN Restart (Most Disruptive - 15 seconds)
```bash
service wan restart
```
**Use when:** Everything else has failed.
**Effect:** Restarts entire WAN subsystem, all clients lose internet briefly.

### Automated Recovery Script

The `/jffs/reconnect-wifi.sh` script tries all methods automatically:

```bash
ssh root@192.168.1.1 '/jffs/reconnect-wifi.sh'
```

**What it does:**
1. Shows current status
2. Tries daemon restart
3. Tries wireless reassociation
4. Tries DHCP renewal
5. Tries interface restart
6. Tries full WAN restart
7. Reports success or failure

**Expected output:**
```
=== Attempting automatic reconnection (all methods) ===

=== Current Wireless Status ===
SSID: "EE WiFi"
Mode: Managed   RSSI: -60 dBm   Channel: 6
...

Method 1: Restarting eewifi-daemon...
✓ Daemon restarted successfully

✓✓✓ Reconnected successfully (daemon restart)
```

### When to Use What

| Symptom | Command | Expected Time |
|---------|---------|---------------|
| Portal login page not working | `/jffs/reconnect-wifi.sh quick` | 3s |
| Can ping 8.8.8.8 but no DNS | `/jffs/reconnect-wifi.sh dhcp` | 3s |
| Can't see "EE WiFi" SSID | `/jffs/reconnect-wifi.sh radio` | 5s |
| No wireless signal at all | `ifconfig eth1 down && ifconfig eth1 up` | 10s |
| Complete failure | `/jffs/reconnect-wifi.sh` (tries all) | 30-60s |

### Diagnostic Commands

**Check what's wrong:**
```bash
# Wireless connection
wl -i eth1 status

# IP address
ifconfig eth1 | grep 'inet addr'

# Internet connectivity
ping -c 3 8.8.8.8

# DNS resolution
nslookup google.com

# Portal login status
wget -qO - --no-check-certificate "https://ee-wifi.ee.co.uk/home" | grep -c "You are now connected"

# Daemon status
/jffs/eewifi-service.sh daemon

# Full diagnostic
/jffs/uplink_status.sh
```

### Creating a Hotkey/Alias

If you're frequently SSH'ing to recover, add this to your local `~/.ssh/config`:

```
Host router-reconnect
    HostName 192.168.1.1
    User root
    RemoteCommand /jffs/reconnect-wifi.sh
    RequestTTY yes
```

Then just run:
```bash
ssh router-reconnect
```

Or create a shell alias:
```bash
alias reconnect='ssh root@192.168.1.1 "/jffs/reconnect-wifi.sh"'
```

### Monitoring Recovery

After running reconnection, monitor logs:
```bash
ssh root@192.168.1.1 'tail -f /var/log/messages | grep -E "eewifi|wifi-reconnect|wireless-monitor"'
```

Look for:
- `wifi-reconnect: ✓✓✓ Reconnected successfully`
- `eewifi-daemon: Authentication to EE WiFi successful`
- `wireless-monitor: CONNECTED`
- `kernel: wl0: link up (eth1)`

### When to Still Reboot

Only reboot if:
1. `/jffs/reconnect-wifi.sh` reports all methods failed
2. Router is completely unresponsive (can't SSH)
3. Web UI is not accessible
4. Logs show kernel panics or system errors

**Before rebooting, save the logs:**
```bash
ssh root@192.168.1.1 'cat /var/log/messages /var/log/messages.0' > ~/router-logs-$(date +%Y%m%d-%H%M).txt
```

This helps diagnose recurring issues.
