#!/usr/bin/bash
set -e

scriptdir="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"

usage() {
    echo "Usage: $0 -n|-k <api_dir>" 1>&2
    echo "Deactivates the API <api_dir>." 1>&2
    echo "Options: -n    Deactivate API <api_dir> in nginx." 1>&2
    echo "         -k    Kill the gunicorn process of API <api_dir>" 1>&2
    echo "         -h    Show this message and exit." 1>&2
}

while getopts "nkh" o; do
    case $o in
        n)
            kill=false
            ;;
        k)
            kill=true
            ;;
        h)
            usage
            exit 0
            ;;
        *)
            usage
            exit 1
            ;;
    esac
done
if ((OPTIND != 2)); then
    echo "ERROR: You must specify either -n or -k." 1>&2
    echo "Type '$0 -h' for help." 1>&2
    exit 1
fi
shift $((OPTIND - 1 ))

if [ ! -d "$1" ]; then
    echo "ERROR: Could not find API directory named '$1'" 1>&2
    echo "Type '$0 -h' for help." 1>&2
    exit 1
fi

name=$(basename "$1")
api_dir=$1
base_dir=$(dirname "$1")
origdir=$(pwd)
cd $base_dir

runinfo="$($scriptdir/status.sh $name)"
ppid="$(cut -d, -f4 <<<"$runinfo")"
url="$(cut -d, -f3 <<<"$runinfo")"
port="$(cut -d, -f5 <<<"$runinfo")"

nginxconf=$base_dir/$name/NGINX.conf
if [[ "$kill" != "true" ]]; then
    if [ -f "$nginxconf" ]; then
        echo "Removing $name from nginx configuration" 1>&2
        rm -f $nginxconf
        echo "Please run/stop other APIs as needed, then 'sudo systemctl reload nginx' to take the configuration live." 1>&2
        echo "After reloading nginx, run 'stop.sh -k $name' to kill $name's process." 1>&2
    else
        echo "The API $name does not have an nginx configuration. Doing nothing. Use 'stop.sh -k $name' to kill $name's process." 1>&2
    fi
elif [ -f "$nginxconf" ]; then
    echo "The API $name is still registered with nginx. Please run 'stop.sh -n $name' first." 1>&2
    echo "Type '$0 -h' for help." 1>&2
    exit 1
else
    if [[ ! -z "$ppid" ]]; then
        kill $ppid
        echo "Stopped $name's process." 1>&2
    else
        echo "ERROR: API $name is not running. Nothing to stop." 1>&2
        echo "Type '$0 -h' for help." 1>&2
    fi
fi

cd $origdir