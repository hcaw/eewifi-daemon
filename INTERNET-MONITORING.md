# Internet Connectivity Monitoring

## Overview

The `internet-monitor.sh` script monitors sustained internet connectivity loss and only alerts when connectivity is lost for an extended period, filtering out brief dropouts.

## Features

- **Smart Filtering**: Only alerts after multiple consecutive failures (default: 3 minutes)
- **Dual Testing**: Uses both ping (8.8.8.8, 1.1.1.1) and DNS resolution tests
- **Recovery Detection**: Logs when connectivity is restored with downtime duration
- **Stateful**: Tracks failure count between runs to avoid false alarms
- **Two Modes**: Can run via cron (recommended) or as a daemon

## Installation

1. Sync to router:
   ```bash
   ./sync-to-router.sh
   ```

2. Add to cron (runs every minute):
   ```bash
   ssh root@192.168.1.1 'cru a internet-monitor "*/1 * * * * /jffs/internet-monitor.sh"'
   ```

3. Verify cron job:
   ```bash
   ssh root@192.168.1.1 'cru l | grep internet'
   ```

## Configuration

Edit the script or set environment variables:

```bash
# Number of consecutive failures before alerting (default: 3)
# 3 = 3 minutes of downtime before alert
FAILURE_THRESHOLD=3

# Mode: 'cron' (default) or 'daemon'
MODE=cron

# Check interval in daemon mode (seconds)
CHECK_INTERVAL=60
```

### Examples

**Alert after 5 minutes of downtime:**
```bash
ssh root@192.168.1.1 'cru a internet-monitor "*/1 * * * * FAILURE_THRESHOLD=5 /jffs/internet-monitor.sh"'
```

**Run as daemon (not recommended, use cron instead):**
```bash
ssh root@192.168.1.1 'MODE=daemon /jffs/internet-monitor.sh &'
```

## Log Messages

### Connection Lost
```
daemon.warn internet-monitor: ✗ Internet connectivity LOST (3 consecutive failures detected)
```

This appears in syslog after 3 consecutive failures (3 minutes down by default).

### Connection Restored
```
daemon.info internet-monitor: ✓ Internet connectivity RESTORED (outage lasted 5 minutes)
```

This appears when connectivity returns, showing how long the outage lasted.

### Silent Behaviour

The script does **not** log anything when:
- Connection is stable and working
- Single or brief failures occur (below threshold)

This prevents log spam and only alerts on real outages.

## Viewing Logs

### Real-time monitoring
```bash
ssh root@192.168.1.1 'tail -f /var/log/messages | grep internet-monitor'
```

### Docker syslog container
```bash
docker exec router-syslog tail -f /var/log/messages | grep internet-monitor
```

### See all internet outages
```bash
docker exec router-syslog grep internet-monitor /var/log/messages
```

## How It Works

1. **Every minute** (via cron), the script runs
2. **Tests connectivity** using:
   - Ping to 8.8.8.8 (Google DNS)
   - Ping to 1.1.1.1 (Cloudflare DNS)
   - DNS resolution of google.com
3. **Tracks failures** in `/var/run/internet-monitor.state`
4. **Alerts only** when consecutive failures reach threshold (default: 3)
5. **Logs restoration** when connectivity returns

### State File

Location: `/var/run/internet-monitor.state`

Contents:
```
CONSECUTIVE_FAILURES=0
LAST_STATE=up
LAST_DOWN_TIME=
```

This file persists state between cron runs. It's stored in `/var/run` (tmpfs), so it's reset on reboot.

## Troubleshooting

### No alerts appearing

Check if cron job is installed:
```bash
ssh root@192.168.1.1 'cru l | grep internet-monitor'
```

Should show:
```
*/1 * * * * /jffs/internet-monitor.sh #internet-monitor#
```

If missing, add it:
```bash
ssh root@192.168.1.1 'cru a internet-monitor "*/1 * * * * /jffs/internet-monitor.sh"'
```

### False positives (alerting too frequently)

Increase the failure threshold:
```bash
# Alert after 5 failures (5 minutes down)
ssh root@192.168.1.1 'cru d internet-monitor'
ssh root@192.168.1.1 'cru a internet-monitor "*/1 * * * * FAILURE_THRESHOLD=5 /jffs/internet-monitor.sh"'
```

### Not alerting when internet is down

Check the state file:
```bash
ssh root@192.168.1.1 'cat /var/run/internet-monitor.state'
```

Manually test connectivity:
```bash
ssh root@192.168.1.1 'ping -c 2 -W 2 8.8.8.8'
```

Force a check:
```bash
ssh root@192.168.1.1 '/jffs/internet-monitor.sh'
```

### Reset state

If state file is corrupted or you want to reset:
```bash
ssh root@192.168.1.1 'rm /var/run/internet-monitor.state'
```

## Integration with Other Monitoring

### Correlation with Wireless Events

See internet outages alongside wireless events:
```bash
docker exec router-syslog grep -E "internet-monitor|wireless-monitor|eewifi-daemon" /var/log/messages | tail -50
```

### Check if outages coincide with channel changes

```bash
docker exec router-syslog grep -E "internet-monitor.*LOST|CHANNEL CHANGED" /var/log/messages
```

This helps identify if internet outages are caused by channel changes or are independent issues.

## Notification Setup (Optional)

### Email Notification

If the router has email configured (Administration → Notifications), you can modify the script to send email alerts:

```bash
# Add to internet-monitor.sh after log_msg for LOST event
if which sendmail >/dev/null 2>&1; then
    echo "Internet connectivity lost" | sendmail admin@example.com
fi
```

### External Webhook

Send alerts to external monitoring service:

```bash
# Add to internet-monitor.sh after log_msg for LOST event
wget -qO - --post-data "status=down" "https://monitoring.example.com/webhook"
```

### Desktop Notification (from laptop)

Create a local script to monitor syslog container and send notifications:

```bash
#!/bin/bash
# internet-monitor-notify.sh
# Run on your laptop

docker exec router-syslog tail -f /var/log/messages | \
  grep --line-buffered "internet-monitor" | \
  while read line; do
    if echo "$line" | grep -q "LOST"; then
        osascript -e 'display notification "Router internet connectivity lost" with title "Router Alert" sound name "Glass"'
    elif echo "$line" | grep -q "RESTORED"; then
        downtime=$(echo "$line" | sed -n 's/.*(outage lasted \([0-9]* minutes\)).*/\1/p')
        osascript -e "display notification \"Internet restored (was down for $downtime)\" with title \"Router Alert\" sound name \"Glass\""
    fi
done
```

## Recommended Configuration

For most users:
- **Failure threshold**: 3 (alerts after 3 minutes down)
- **Mode**: cron (simpler, more reliable than daemon)
- **Check interval**: 1 minute (via cron schedule)

This provides a good balance between:
- Fast detection of real outages
- Filtering out brief dropouts
- Low resource usage
- Minimal log spam

## Files

- `/jffs/internet-monitor.sh` - Main monitoring script
- `/var/run/internet-monitor.state` - State file (tmpfs, lost on reboot)
- `/var/log/messages` - Syslog destination for alerts

## See Also

- [MONITORING.md](MONITORING.md) - Wireless connection monitoring
- [RECONNECTION-GUIDE.md](RECONNECTION-GUIDE.md) - Manual recovery procedures
- [CHANNEL-MONITORING.md](CHANNEL-MONITORING.md) - How to view channel changes
