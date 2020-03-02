#!/usr/bin/bash
set -e

logpath="/var/log/mllp"

if [ ! -d "$1" ]; then
    echo "Could not find API directory named '$1'"
    exit 1
fi

port="$2"
if [[ "$port" = "auto" ]];then
    port=$(./findport.sh)
fi

numre='^[0-9]+$'
if ! [[ $port =~ $numre ]]; then
    echo "Second argument must be a free port number or 'auto'"
    exit 2
fi

name=$(basename "$1")
directory=$1
origdir=$(pwd)

runinfo="$(./status.sh $name)"
ppid="$(cut -d, -f4 <<<"$runinfo")"

if [[ ! -z "$ppid" ]]; then
    echo "The API $name is already running as process $ppid. Aborting."
    exit 3
fi

echo "Setting environment variables for [$name] from envvars.ini..."
myvar=$(grep -vE "^\s*#|^$" envvars.ini | sed -nr "/^\[$name\]/,/^\[/p" | grep -v "\[")
while read line; do
    varname="$(cut -d= -f1 <<<$line)"
    value="$(cut -d= -f2 <<<$line)"
    value_dec="$(base64 -d <<<$value)"
    echo "Setting environment variable '$varname'"
    declare $varname=$value_dec
    export $varname
done <<< "$myvar"

cd $directory
echo "Activating Python environment for API $name..."
source .venv/bin/activate

echo "Starting Gunicorn daemon..."
gunicorn="$(pwd)/.venv/bin/python3 -m gunicorn.app.wsgiapp"
$gunicorn "${@:3}" --daemon --log-file $logpath/$name.log --capture-output --workers 1 --bind 127.0.0.1:$port mllaunchpad.wsgi
#$gunicorn "${@:3}" --daemon --log-file $logpath/$name.log --capture-output --workers 1 --bind 127.0.0.1:$port mllaunchpad.wsgi

deactivate

cd $origdir

waiting=10
runinfo="$(./status.sh $name)" 2>/dev/null
ppid="$(cut -d, -f4 <<<"$runinfo")"
while [[ -z "$ppid" ]]; do
    sleep 1
    runinfo="$(./status.sh $name)" 2>/dev/null
    ppid="$(cut -d, -f4 <<<"$runinfo")"
    echo -n "."
    let waited--
    if (( $waiting <= 0 )); then
        echo "Could not start API $name."
        exit 4
    fi
done
echo "Started."

nginxconf=$name/NGINX.conf
echo "Creating NGINX configuration fragment for this API in $nginxconf"
url="$(cut -d, -f3 <<<"$runinfo")"
port="$(cut -d, -f5 <<<"$runinfo")"
echo "location /$url {">$nginxconf
echo "    proxy_pass http://127.0.0.1:$port/$url;">>$nginxconf
echo "}">>$nginxconf

echo "Started Gunicorn daemon for API $name on 127.0.0.1:$port."
echo "Logging to $logpath/$name.log. Use status.sh to check for running/stopped APIs. Current status:"
./status.sh
echo "Use stop.sh <api> to stop APIs."
echo "Run 'sudo nginx -s reload' when done starting/stopping APIs to take the changes live."

