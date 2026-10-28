# EE WiFi Connection Monitoring

This document describes the monitoring and logging features for tracking wireless connection stability and channel changes.

## Overview

Three layers of monitoring are now active:

1. **Enhanced eewifi-daemon** - Tracks connection state changes
2. **wireless-monitor** - Dedicated monitoring script (runs every minute)
3. **FreshTomato wireless debug** - Low-level driver messages

## 1. Enhanced eewifi-daemon Logging

### What It Logs

The daemon now tracks and logs:

- **Initial connection**: When first connecting to "EE WiFi" SSID
  ```
  [Log excerpt removed - not kept in source control]
  ```

- **Disconnection**: When connection to the SSID is lost
  ```
  [Log excerpt removed - not kept in source control]
  ```

- **Reconnection**: When reconnecting after a disconnection
  ```
  [Log excerpt removed - not kept in source control]
  ```

- **AP change**: When connecting to a different access point (different BSSID)
  ```
  [Log excerpt removed - not kept in source control]
  ```

- **Channel change**: When the AP changes channel
  ```
  [Log excerpt removed - not kept in source control]
  ```

### How It Works

- Runs continuously as part of the main daemon loop
- Checks connection details every cycle (2s when disconnected, 60s when connected)
- Compares current state with previous state
- Logs significant changes immediately

## 2. Wireless Monitor Script

### What It Does

Standalone monitoring script that tracks wireless connection health:

- **Connection status**: Detects connect/disconnect events
- **AP roaming**: Detects when switching between access points
- **Channel changes**: Logs channel changes
- **Signal strength**: Alerts on significant RSSI changes (>10 dBm)
- **IP address changes**: Tracks DHCP renewals/changes

### Log Examples

**Initial connection:**
```
[Log excerpt removed - captured from router syslog; not kept in source control]
```

**Disconnection:**
```
[Log excerpt removed - captured from router syslog; not kept in source control]
```

**Channel change:**
```
[Log excerpt removed - captured from router syslog; not kept in source control]
```

**AP change (roaming):**
```
[Log excerpt removed - captured from router syslog; not kept in source control]
```

**Signal degradation:**
```
[Log excerpt removed - captured from router syslog; not kept in source control]
```

**IP change:**
```
[Log excerpt removed - captured from router syslog; not kept in source control]
```

### Cron Schedule

Runs every minute:
```
*/1 * * * * /jffs/wireless-monitor.sh
```

### State File

Maintains state in `/var/run/wireless-monitor.state` to track changes between runs.

## 3. FreshTomato Wireless Debug

### What It Logs

Low-level wireless driver messages sent to syslog as `kern.warn` messages:

**Disconnection events:**
```
[Log excerpt removed - captured from router syslog; not kept in source control]
```

**Reconnection events:**
```
kern.warn kernel: wl0: link up (eth1)
```

### Current Settings

```bash
wl -i eth1 msglevel 0x7
# 0x1 - error (error messages)
# 0x2 - trace (association/disassociation events)
# 0x4 - prhdrs (link up/down messages)
```

**Note:** The original minimal setting (`0x80002`) produced no output. The moderate setting (`0x7`) provides good visibility without excessive noise. For maximum verbosity, use `0x8001f` (includes packet-level details but clutters logs).

### Making It Persistent

The debug logging is currently active but will be lost on reboot. To make it permanent:

**Option 1: Via init script** (recommended)
1. Log into FreshTomato Web UI
2. Go to **Administration → Scripts → Init**
3. Add: `/jffs/enable-wireless-debug.sh`
4. Save

**Option 2: Manually enable on each boot**
```bash
ssh root@192.168.1.1 '/jffs/enable-wireless-debug.sh'
```

## Viewing Logs

### Live monitoring (all wireless events):
```bash
ssh root@192.168.1.1 'tail -f /var/log/messages | grep -E "eewifi|wireless"'
```

### Just daemon events:
```bash
ssh root@192.168.1.1 'tail -f /var/log/messages | grep eewifi-daemon'
```

### Just wireless monitor:
```bash
ssh root@192.168.1.1 'tail -f /var/log/messages | grep wireless-monitor'
```

### Recent connection changes (last hour):
```bash
ssh root@192.168.1.1 'grep -E "CONNECTED|DISCONNECTED|CHANNEL|AP CHANGED" /var/log/messages | tail -20'
```

### Summary of today's events:
```bash
ssh root@192.168.1.1 'grep -E "eewifi-daemon.*(Connected|Disconnected|changed)" /var/log/messages'
```

## What to Watch For

### Normal Operation

You should see:
- Periodic "Already logged in" debug messages (every 60s)
- Wireless monitor running from cron every minute (visible in cron.info logs)
- Stable BSSID, channel, and IP

### Channel Change Event

Expected sequence when EE WiFi changes channel:
1. `wireless-monitor: DISCONNECTED` (connection lost)
2. 5-15 seconds of silence (scanning for SSID)
3. `eewifi-daemon: Connected to 'EE WiFi' SSID` (reconnected on new channel)
4. `wireless-monitor: CHANNEL CHANGED: X -> Y`
5. `eewifi-daemon: Not logged in to EE WiFi, attempting authentication`
6. `eewifi-daemon: Authentication to EE WiFi successful`

### Warning Signs

Watch for:
- **Frequent disconnections**: Multiple DISCONNECTED messages per hour
- **Failed authentications**: Repeated "Authentication failed" messages
- **Excessive roaming**: Switching between BSSIDs frequently
- **Poor signal**: RSSI worse than -75 dBm consistently

## Troubleshooting

### No wireless-monitor logs appearing

Check if cron job is installed:
```bash
ssh root@192.168.1.1 'cru l | grep wireless'
```

Should show:
```
*/1 * * * * /jffs/wireless-monitor.sh #wireless-monitor#
```

If missing, re-add:
```bash
ssh root@192.168.1.1 'cru a wireless-monitor "*/1 * * * * /jffs/wireless-monitor.sh"'
```

### Daemon not logging connection changes

Check daemon is running with updated code:
```bash
ssh root@192.168.1.1 'ps | grep eewifi-daemon'
```

Restart daemon:
```bash
ssh root@192.168.1.1 '/jffs/eewifi-service.sh restart'
```

### Too many debug messages

The daemon respects the DEBUG flag. To reduce verbosity, ensure DEBUG is not set in the config:
```bash
ssh root@192.168.1.1 'grep DEBUG /jffs/eewifi-daemon.config'
```

Should show DEBUG not set, or DEBUG=false.

## Statistics & Analysis

### Count disconnections today:
```bash
ssh root@192.168.1.1 'grep "$(date +"%b %_d")" /var/log/messages | grep -c DISCONNECTED'
```

### Average uptime between disconnections:
```bash
ssh root@192.168.1.1 'grep -E "CONNECTED|DISCONNECTED" /var/log/messages | tail -20'
```

### Channel change history:
```bash
ssh root@192.168.1.1 'grep "CHANNEL CHANGED" /var/log/messages'
```

## Files

- `/jffs/eewifi-daemon.sh` - Main daemon (now with connection tracking)
- `/jffs/wireless-monitor.sh` - Standalone monitoring script
- `/jffs/enable-wireless-debug.sh` - Enable FreshTomato wireless debug
- `/var/run/wireless-monitor.state` - Monitor state file (ephemeral)
- `/var/log/messages` - System log (where all messages go)
