#!/usr/bin/bash
set -e

scriptdir="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"

usage() {
    echo "Usage: $0 <api_dir>" 1>&2
    echo "Reloads <api_dir>, e.g. to put an updated model live." 1>&2
    echo "This signals HUP to Gunicorn's master process, which will trigger a graceful reload." 2>&2
    echo "NOTE: When (re)deploying a deliverable, use deploy.sh instead" 1>&2
    echo "Options: -t    Train the model before reloading" 1>&2
    echo "         -h    Show this message and exit." 1>&2
}

while getopts "th" o; do
    case $o in
        t)
            train=true
            ;;
        *)
            usage
            exit 1
            ;;
    esac
done
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

if [ "$train" = "true" ]; then
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

    echo "Starting training for $name..." 1>&2
    cd $name
    source .venv/bin/activate
    python -m mllaunchpad --version 2>&1 | grep "version 0"
    if [ $? == 0 ]; then
        python -m mllaunchpad --train
    else
        python -m mllaunchpad train
    fi
    deactivate
    echo "Finished training of $name." 1>&2
fi

nginxconf=$base_dir/$name/NGINX.conf
if [[ ! -z "$ppid" ]]; then
    kill -HUP $ppid
    echo "Reloaded process $ppid of $name." 1>&2
else
    echo "ERROR: API $name is not running. Nothing to stop." 1>&2
    echo "To start a non-running API, use run.sh." 1>&2
    echo "Type '$0 -h' for help." 1>&2
fi

cd $origdir
