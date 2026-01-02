# EE WiFi Auto-Login Daemon

Auto-login daemon for [EE WiFi](https://ee-wifi.ee.co.uk/) captive portals, designed for embedded Linux routers running **FreshTomato** firmware.

Automatically authenticates when connected to an "EE WiFi" SSID and maintains the login session.

## Target Environment

- **Router**: Netgear R7000 (or similar Broadcom-based)
- **Firmware**: FreshTomato 2025.4 K26ARM
- **Shell**: BusyBox ash (POSIX-compliant, no bashisms)
- **Persistent storage**: `/jffs/`

## Scripts

| Script | Purpose |
|--------|---------|
| `eewifi-daemon.sh` | Background daemon that monitors SSID and auto-logs in |
| `eewifi-service.sh` | Service controller for login/logout/status/daemon management |
| `uplink_status.sh` | Diagnostic tool for wireless uplink status |

## Installation

1. Copy scripts to router:
   ```sh
   # From your local machine
   cat eewifi-daemon.sh | ssh root@192.168.1.1 "cat > /jffs/eewifi-daemon.sh && chmod +x /jffs/eewifi-daemon.sh"
   cat eewifi-service.sh | ssh root@192.168.1.1 "cat > /jffs/eewifi-service.sh && chmod +x /jffs/eewifi-service.sh"
   ```

2. Create config file on router:
   ```sh
   ssh root@192.168.1.1 "cat > /jffs/eewifi-daemon.config" << 'EOF'
   USERNAME="your-email@example.com"
   PASSWORD="your-password"
   DEBUG=false
   DELAY_INTERFACE=2
   DELAY_LOGIN_ATTEMPTS=5
   DELAY_SUCCESS=60
   WGET_TIMEOUT=5
   SERVER="https://ee-wifi.ee.co.uk"
   EOF
   ```

3. Configure automatic startup via nvram:
   ```sh
   ssh root@192.168.1.1 "nvram set script_wanup='/jffs/eewifi-service.sh start'; nvram commit"
   ```

## Usage

### Service Controller

```sh
# Check current status
/jffs/eewifi-service.sh status

# Show full info (SSID, login status, daemon status)
/jffs/eewifi-service.sh info

# Manual login/logout
/jffs/eewifi-service.sh login
/jffs/eewifi-service.sh logout

# Daemon control
/jffs/eewifi-service.sh start
/jffs/eewifi-service.sh stop
/jffs/eewifi-service.sh restart
/jffs/eewifi-service.sh daemon   # check if running
```

### Diagnostics

```sh
# Basic uplink status
/jffs/uplink_status.sh

# With connectivity tests
PINGS=1 /jffs/uplink_status.sh

# With DNS test
DNS_TEST=1 /jffs/uplink_status.sh

# With wireless scan
SCAN=1 /jffs/uplink_status.sh
```

### Debug Mode

Run daemon in foreground with verbose output:
```sh
DEBUG=true /jffs/eewifi-daemon.sh
```

## Configuration Options

| Variable | Default | Description |
|----------|---------|-------------|
| `USERNAME` | - | EE WiFi account email |
| `PASSWORD` | - | EE WiFi account password |
| `DEBUG` | `false` | Enable verbose output |
| `DELAY_INTERFACE` | `2` | Seconds between SSID checks when not on EE WiFi |
| `DELAY_LOGIN_ATTEMPTS` | `5` | Seconds between failed login retries |
| `DELAY_SUCCESS` | `60` | Seconds between checks when logged in |
| `WGET_TIMEOUT` | `5` | HTTP request timeout in seconds |
| `SERVER` | `https://ee-wifi.ee.co.uk` | EE WiFi login server |

## BusyBox Compatibility

These scripts are written for BusyBox ash. Key constraints:

- Use `.` instead of `source`
- Use `[ ]` instead of `[[ ]]`
- Use `which` instead of `command -v`
- Use `-T SEC` instead of `--timeout=SEC` for wget
- No `--no-cache` option for wget

## Network Topology

When connected to EE WiFi:
- Router WAN IP: CGNAT address (100.x.x.x/16)
- Login server: ee-wifi.ee.co.uk (109.144.192.50)

## Troubleshooting

**Login fails silently**: BusyBox wget may report "too many redirections" but the login still succeeds. The scripts verify login by checking the status page after POST.

**SSID not detected**: The scripts use the Broadcom `wl` utility. Check manually:
```sh
wl -i eth1 status | grep SSID
```

**Daemon not starting at boot**: Verify nvram setting:
```sh
nvram get script_wanup
```

## License

MIT License - see [LICENSE](LICENSE)

## Credits

Originally based on [btwifi-daemon](https://github.com/adrianrobinson/btwifi-daemon) by Adrian Robinson.
