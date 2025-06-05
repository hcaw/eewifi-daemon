# eewifi-daemon

- Shell script to maintain a [EE WiFi](https://ee-wifi.ee.co.uk/public/ee/index.htm) login
- Intended for OpenWRT access points, such as the [GL-iNET](https://www.gl-inet.com/) routers
- Runs in the background or interactively for debugging
- supplies username and password from eewifi-daemon.config

## Interactive Usage:

```
$ eewifi-daemon.sh
```

## Background Task:

Add this to the bottom of `/etc/rc.local`:

```
$ echo /path/to/eewifi-daemon.sh & >> /etc/rc.local
```
