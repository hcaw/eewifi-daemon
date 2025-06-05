#!/bin/sh
# Copyright 2025 Adrian Robinson
# Updated to support latest EE WiFi Login, and OpenWRT 22.03
#
# add this to the bottom of /etc/rc.local:
# /path/to/wifi-daemon.sh &

# location of the config file (include absolute path)
CONFIG_FILE="/root/wifi-daemon.config"

# static options
WGET="wget -qO - --no-check-certificate --no-cache"

# load external config file for login details
if [ -e $CONFIG_FILE ]; then
    source $CONFIG_FILE
else
    echo "Error, config file '${CONFIG_FILE}' could not be found!"
    exit 1
fi

check_tool() {
    local command=$1
    if ! command -v "$command" >/dev/null; then
        echo -e "Error, command '$command' could not be found!"
        exit 1
    fi
}
check_tool iwinfo
check_tool wget
check_tool logger

while true; do
    if [[ $(iwinfo $INTERFACE info | grep -c "EE WiFi") == 1 ]]; then
        if [[ "$DEBUG" == 'true' ]]; then echo "Info: You're connected to 'EE WiFi' access point"; fi
        serverResponse=$($WGET --timeout $WGET_TIMEOUT "$SERVER/home")
        isLoggedIn=$(echo $serverResponse | grep -c "You are now connected")
        if [[ $isLoggedIn == 1 ]]; then
            if [[ "$DEBUG"  == 'true' ]]; then echo "Info: You're logged in to EE WiFi!"; fi
            if [[ "$DEBUG"  == 'true' ]]; then echo "Info: Sleeping for $DELAY_SUCCESS seconds..."; fi
            sleep $DELAY_SUCCESS
        else
            if [[ "$DEBUG"  == 'true' ]]; then echo "Info: You're not logged in to EE WiFi"; fi
             if [[ "$DEBUG"  == 'true' ]]; then echo "Info: Attempting login"; fi
            serverResponse=$($WGET --timeout $WGET_TIMEOUT --post-data "inputUsername=$USERNAME&username=wam/$USERNAME&password=$PASSWORD&xhtmlLogon=$SERVER/ante" "$SERVER/ante")
            isAuthenticated=$(echo $serverResponse | grep -c "You are now connected")
            if [[ $isAuthenticated == 1 ]]; then
                if [[ "$DEBUG"  == 'true' ]]; then echo "Success: Authenticating to EE WiFi was successful!"; fi
                if [[ "$DEBUG"  == 'true' ]]; then logger -t eewifi "Success: Authenticating to EE WiFi was successful"; fi
                if [[ "$DEBUG"  == 'true' ]]; then echo "Info: Sleeping for $DELAY_SUCCESS seconds..."; fi
                sleep $DELAY_SUCCESS
            else
                if [[ "$DEBUG"  == 'true' ]]; then echo "Error: Authenticating to EE WiFi was unsuccessful"; fi
                if [[ "$DEBUG"  == 'true' ]]; then echo "Info: Sleeping for $DELAY_LOGIN_ATTEMPTS seconds..."; fi
                sleep $DELAY_LOGIN_ATTEMPTS
            fi
        fi
    else
        if [[ "$DEBUG"  == 'true' ]]; then echo "Error: You're not connected to 'EE WiFi' access point"; fi
        if [[ "$DEBUG"  == 'true' ]]; then echo "Info: Sleeping for $DELAY_INTERFACE seconds..."; fi
        sleep $DELAY_INTERFACE
    fi
done