# Channel Change Monitoring Guide

This guide shows how to monitor and view wireless channel change events using various tools.

## Quick Reference

### View Channel Changes in Real-time

```bash
# SSH to router and monitor live
ssh root@192.168.1.1 'tail -f /var/log/messages | grep -E "CHANNEL CHANGED|Channel changed"'
```

### View Channel Changes in Docker Logs

```bash
# Inside the syslog-ng container
docker exec router-syslog tail -f /var/log/messages | grep -E "CHANNEL CHANGED|Channel changed"

# Or from host
docker exec router-syslog grep -E "CHANNEL CHANGED|Channel changed" /var/log/messages
```

## Using lnav for Channel Monitoring

### Method 1: Simple Search in lnav

1. Open the log file in lnav:
   ```bash
   docker exec -it router-syslog lnav /var/log/messages
   ```
   Or locally:
   ```bash
   lnav ~/router-logs/messages.txt
   ```

2. Press `/` to search and type:
   ```
   CHANNEL CHANGED|Channel changed
   ```

3. Press `n` to jump to next match, `N` for previous match

### Method 2: Filter View in lnav

1. Open lnav as above

2. Press `;` to open SQL query mode

3. Use this SQL filter to show only channel changes:
   ```sql
   SELECT * FROM logline WHERE log_body LIKE '%CHANNEL CHANGED%' OR log_body LIKE '%Channel changed%'
   ```

4. Or use lnav's filter expressions (press `CTRL+F`):
   ```
   log_body :CHANNEL CHANGED|Channel changed:
   ```

### Method 3: Create Custom lnav Format (Advanced)

Create `~/.lnav/formats/installed/wireless-events.json`:

```json
{
  "wireless_events": {
    "title": "Wireless Channel Events",
    "description": "Highlights wireless channel changes",
    "file-pattern": "messages.*",
    "highlights": {
      "channel-change": {
        "pattern": "CHANNEL CHANGED: (\\d+) -> (\\d+)",
        "color": "yellow",
        "underline": true
      }
    }
  }
}
```

Then reload lnav and channel changes will be highlighted.

## Using grep for Channel Analysis

### Extract All Channel Changes

```bash
# From router
ssh root@192.168.1.1 'grep -E "CHANNEL CHANGED|Channel changed" /var/log/messages'

# From docker container
docker exec router-syslog grep -E "CHANNEL CHANGED|Channel changed" /var/log/messages
```

### Show Channel Changes with Context

```bash
# Show 5 lines before and after each channel change
docker exec router-syslog grep -E -C 5 "CHANNEL CHANGED|Channel changed" /var/log/messages
```

### Count Channel Changes Per Day

```bash
# Count total channel changes
docker exec router-syslog grep -c "CHANNEL CHANGED" /var/log/messages

# Count by date
docker exec router-syslog grep "CHANNEL CHANGED" /var/log/messages | awk '{print $1, $2, $3}' | sort | uniq -c
```

### Create Channel Change Timeline

```bash
# Extract just timestamps and channel changes
docker exec router-syslog grep "CHANNEL CHANGED" /var/log/messages | \
  awk '{print $1, $2, $3, $(NF-3), $(NF-2), $(NF-1), $NF}'
```

Expected output:
```
Jan 4 02:54:00 CHANNEL CHANGED: 1 -> 6
Jan 5 09:05:23 CHANNEL CHANGED: 6 -> 1
Jan 5 12:20:15 CHANNEL CHANGED: 1 -> 6
```

## Log Message Formats

### Channel change events are logged by two sources:

**1. wireless-monitor (every minute):**
```
[Log excerpt removed - captured from router syslog; not kept in source control]
```

**2. eewifi-daemon (continuous):**
```
[Log excerpt removed - captured from router syslog; not kept in source control]
```

Both are equivalent and indicate the same event.

## Viewing Channel Changes with Other Events

### See Full Reconnection Sequence

```bash
# Show channel change with surrounding events
docker exec router-syslog grep -E "CHANNEL|CONNECTED|DISCONNECTED" /var/log/messages | tail -20
```

Example output showing a channel change:
```
[Log excerpt removed - captured from router syslog; not kept in source control]
```

### View Channel Changes with Kernel Events

```bash
# Include kernel link up/down messages
docker exec router-syslog grep -E "CHANNEL|wl0: link" /var/log/messages
```

## Creating a Channel Change Alert Script

If you want a notification when channel changes (beyond just logging):

```bash
#!/bin/bash
# channel-change-notifier.sh
# Run on your laptop, monitors docker logs for channel changes

docker exec router-syslog tail -f /var/log/messages | grep --line-buffered "CHANNEL CHANGED" | while read line; do
    # Extract old and new channel
    old_ch=$(echo "$line" | sed -n 's/.*CHANNEL CHANGED: \([0-9]*\) -> \([0-9]*\).*/\1/p')
    new_ch=$(echo "$line" | sed -n 's/.*CHANNEL CHANGED: \([0-9]*\) -> \([0-9]*\).*/\2/p')

    # Send notification (macOS)
    osascript -e "display notification \"Channel changed from $old_ch to $new_ch\" with title \"EE WiFi Channel Change\""

    # Or play a sound
    # afplay /System/Library/Sounds/Glass.aiff

    # Or send to Slack/Discord/Email
    # curl -X POST ... webhook URL
done
```

## Automated Analysis Script

Create a script to analyse channel change patterns:

```bash
#!/bin/bash
# channel-analysis.sh
# Analyses channel change frequency and patterns

echo "=== Channel Change Analysis ==="
echo ""

# Total changes
total=$(docker exec router-syslog grep -c "CHANNEL CHANGED" /var/log/messages 2>/dev/null || echo 0)
echo "Total channel changes: $total"
echo ""

# Changes by date
echo "Changes per day:"
docker exec router-syslog grep "CHANNEL CHANGED" /var/log/messages | \
  awk '{print $1, $2}' | sort | uniq -c | awk '{print "  ", $2, $3, ":", $1, "changes"}'
echo ""

# Most common transitions
echo "Most common channel transitions:"
docker exec router-syslog grep "CHANNEL CHANGED" /var/log/messages | \
  sed -n 's/.*CHANNEL CHANGED: \([0-9]* -> [0-9]*\).*/\1/p' | \
  sort | uniq -c | sort -rn | head -5 | \
  awk '{print "  ", $2, $3, $4, ":", $1, "times"}'
echo ""

# Average time between changes
echo "First change: $(docker exec router-syslog grep "CHANNEL CHANGED" /var/log/messages | head -1 | awk '{print $1, $2, $3}')"
echo "Last change:  $(docker exec router-syslog grep "CHANNEL CHANGED" /var/log/messages | tail -1 | awk '{print $1, $2, $3}')"
```

## Correlation with Disconnections

To see if channel changes correlate with connection issues:

```bash
# Show channel changes alongside DISCONNECTED events
docker exec router-syslog grep -E "CHANNEL CHANGED|DISCONNECTED" /var/log/messages | \
  awk '{print $1, $2, $3, $(NF-5), $(NF-4), $(NF-3), $(NF-2), $(NF-1), $NF}'
```

This helps identify whether:
- Channel changes cause disconnections
- Disconnections happen independent of channel changes
- Channel changes are handled smoothly

## Recommended Setup

For convenient monitoring:

1. **Add shell alias** to your `~/.bashrc` or `~/.zshrc`:
   ```bash
   alias channel-changes='docker exec router-syslog grep "CHANNEL CHANGED" /var/log/messages'
   alias watch-channels='docker exec router-syslog tail -f /var/log/messages | grep --line-buffered -E "CHANNEL|CONNECTED"'
   ```

2. **Create lnav bookmark** (press `m` in lnav on a channel change line to bookmark)

3. **Set up desktop notifications** using the channel-change-notifier.sh script above

## Files

- `/var/log/messages` on router (tmpfs, lost on reboot)
- `/var/log/messages` in syslog-ng docker container (persistent)
- `/jffs/wireless-monitor.sh` - Script that detects and logs channel changes
- `/jffs/eewifi-daemon.sh` - Daemon that also tracks channel changes
