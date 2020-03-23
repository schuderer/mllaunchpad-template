#!/usr/bin/bash
set -e

logpath="$(cat LOGPATH.txt)"
scriptdir="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"

usage() {
    echo "Usage: $0 -a|-p <port> <api_dir>" 1>&2
    echo "Runs the API <api_dir> locally and adds it to the nginx configuration." 1>&2
    echo "NOTE: You still need to activate the nginx configuration yourself using 'sudo systemctl reload nginx'." 1>&2
    echo "Options: -p <port>  Listen to local port number <port>" 1>&2
    echo "         -a         Automatically choose local port" 1>&2
    echo "         -h         Show this message and exit." 1>&2
}

while getopts "ap:h" o; do
    case $o in
        a)
            port=$(./findport.sh)
            ;;
        p)
            port=$OPTARG
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
if ((OPTIND == 1)); then
    echo "ERROR: You must specify either -a or -p." 1>&2
    echo "Type '$0 -h' for help." 1>&2
    exit 1
fi
shift $((OPTIND - 1 ))

if [ ! -d "$1" ]; then
    echo "ERROR: Could not find API directory named '$1'" 1>&2
    echo "Type '$0 -h' for help." 1>&2
    exit 1
fi

numre='^[0-9]+$'
if ! [[ $port =~ $numre ]]; then
    echo "ERROR: <port> must be a free port number" 1>&2
    echo "Type '$0 -h' for help." 1>&2
    exit 2
fi

name=$(basename "$1")
api_dir=$1
base_dir=$(dirname "$1")
origdir=$(pwd)
cd $base_dir

runinfo="$($scriptdir/status.sh $name)"
ppid="$(cut -d, -f4 <<<"$runinfo")"

if [[ ! -z "$ppid" ]]; then
    echo "ERROR: The API $name is already running as process $ppid. Aborting." 1>&2
    echo "Type '$0 -h' for help." 1>&2
    exit 3
fi

echo "Setting environment variables for [$name] from envvars.ini..." 1>&2
mkfifo mypipe_$name
grep -vE "^\s*#|^$" "$base_dir/envvars.ini" | sed -nr "/^\[$name\]/,/^\[/p" | grep -v "\[" > mypipe_$name &
while read line; do
    varname="$(cut -d= -f1 <<<$line)"
    value="$(cut -d= -f2- <<<$line)"
    value_dec="$(base64 -d <<<$value)"
    echo "Setting environment variable '$varname'" 1>&2
    declare $varname=$value_dec
    export $varname
done < mypipe_$name
rm mypipe_$name

cd $api_dir
echo "Activating Python environment for API $name..." 1>&2
source .venv/bin/activate

echo "Starting Gunicorn daemon..." 1>&2
gunicorn="$(pwd)/.venv/bin/python3 -m gunicorn.app.wsgiapp"
$gunicorn "${@:3}" --daemon --log-file $logpath/$name.log --capture-output --workers 4 --bind 127.0.0.1:$port mllaunchpad.wsgi
#$gunicorn "${@:3}" --daemon --log-file $logpath/$name.log --capture-output --workers 1 --bind 127.0.0.1:$port mllaunchpad.wsgi

deactivate

cd $scriptdir

sleep 1
waiting=10
runinfo="$(./status.sh $name)" 2>/dev/null
ppid="$(cut -d, -f4 <<<"$runinfo")"
while [[ -z "$ppid" ]]; do
    runinfo="$(./status.sh $name)" 2>/dev/null
    ppid="$(cut -d, -f4 <<<"$runinfo")"
    echo -n "."
    let waited--
    if (( $waiting <= 0 )); then
        echo "ERROR: Could not start API $name." 1>&2
        echo "Type '$0 -h' for help." 1>&2
        exit 4
    fi
    sleep 1
done
echo "Started." 1>&2

nginxconf=$base_dir/$name/NGINX.conf
echo "Creating NGINX configuration fragment for this API in $nginxconf" 1>&2
url="$(cut -d, -f3 <<<"$runinfo")"
port="$(cut -d, -f5 <<<"$runinfo")"
echo "location /$url {">$nginxconf
echo "    proxy_pass http://127.0.0.1:$port/$url;">>$nginxconf
echo "}">>$nginxconf
chmod o+r "$nginxconf"

echo "Started Gunicorn daemon for API $name on 127.0.0.1:$port." 1>&2
echo "Logging to $logpath/$name.log. Use status.sh to check for running/stopped APIs." 1>&2
echo "Use stop.sh <api> to stop APIs." 1>&2
echo "Run 'sudo systemctl reload nginx' when done starting/stopping APIs to take the changes live." 1>&2

cd $origdir
