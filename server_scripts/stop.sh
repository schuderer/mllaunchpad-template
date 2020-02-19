#!/usr/bin/bash
set -e

if [ ! -d "$1" ]; then
    echo "Could not find API directory named '$1'"
    exit 1
fi

name=$(basename "$1")

runinfo="$(./status.sh $name)"
ppid="$(cut -d, -f4 <<<"$runinfo")"
url="$(cut -d, -f3 <<<"$runinfo")"
port="$(cut -d, -f5 <<<"$runinfo")"

if [[ "$2" != "-f" ]]; then
    if [ -f $name/NGINX.conf ]; then
        echo "Removing $name from nginx configuration"
        rm -f $name/NGINX.conf
        echo "Please run/stop other APIs as needed, then 'sudo nginx -s reload' to take the configuration live."
        echo "After reloading nginx, run 'stop.sh $name -f' to kill $name's process."
    else
        echo "The API $name does not have an nginx configuration. Use 'stop.sh $name -f' to kill $name's process."
    fi
elif [ -f "$name/NGINX.conf" ]; then
    echo "The API $name is still registered with nginx. Please run 'stop.sh $name' without the -f option first."
else
    if [[ ! -z "$ppid" ]]; then
        kill $ppid
        echo "Stopped $name's process."
    else
        echo "Nothing to stop."
    fi
fi
