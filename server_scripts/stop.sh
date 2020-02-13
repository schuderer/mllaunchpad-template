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

if [[ ! -z "$ppid" ]]; then
    kill $ppid
    echo "Stopped $name. I trust that you have removed 127.0.0.1:$port/$url from the nginx configuration."
else
    echo "Nothing to stop."
fi
