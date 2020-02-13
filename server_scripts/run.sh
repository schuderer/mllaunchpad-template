#!/usr/bin/bash
set -e

logpath="/var/log/mllp"

if [ ! -d "$1" ]; then
    echo "Could not find API directory named '$1'"
    exit 1
fi

numre='^[0-9]+$'
if ! [[ $2 =~ $numre ]]; then
    echo "Second argument must be a port number"
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

cd $directory
echo "Activating Python environment for API $name..."
source .venv/bin/activate

echo "Starting Gunicorn daemon..."
gunicorn="$(pwd)/.venv/bin/python3 -m gunicorn.app.wsgiapp"
$gunicorn "${@:3}" --daemon --log-file $logpath/$name.log --capture-output --workers 1 --bind 127.0.0.1:$2 mllaunchpad.wsgi

deactivate
cd $origdir

echo "Started Gunicorn daemon for API $name on 127.0.0.1:$2."
echo "Logging to $logpath/$name.log. Use status.sh to check for running/stopped APIs."
echo "Use stop.sh <api> to stop APIs."

