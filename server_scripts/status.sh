#!/usr/bin/bash

scriptdir="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"

usage() {
    echo "Usage: $0 [-q] [api_dir]" 1>&2
    echo "Outputs status of all APIs or of API <api_dir> (if specified)." 1>&2
    echo "The output columns are: api_name, base_url, process, local_port" 1>&2
    echo "Options: -q    Quiet mode (suppress helpful messages)." 1>&2
    echo "         -h    Show this message and exit." 1>&2
}

while getopts ":qh" o; do
    case $o in
        q)
            quiet="1"
            ;;
        h)
            usage
            exit 0
            ;;
    esac
done
shift $((OPTIND - 1 ))

getstatus() {
    if [ ! -d "$1" ]; then
        echo "ERROR: Could not find API directory named '$1'" 1>&2
        echo "Type '$0 -h' for help." 1>&2
        exit 1
    fi

    name=$(basename "$1")
    directory=$1
    origdir=$(pwd)
    cd $directory

    fullpath="$(pwd)"

    ok=NOK
    if [ -d "$fullpath/.venv" ]; then
        ok=OK
    fi
    innginx=
    if [ -f "$fullpath/NGINX.conf" ]; then
        innginx=nginx
    fi
    url="$(cat $fullpath/LAUNCHPAD_BASE_URL.txt)"
    # ps's H option prints hierarchically, with parent processes before child processes
    # so we can just take the first matching line, which will be the parent process.
    line="$(ps -efH | grep -v grep | grep -m 1 "$fullpath/\.venv")"
    port="$(sed -r "s/^.*127.0.0.1:([[:digit:]]+).*$/\1/g" <<<"$line")"
    ppid="$(sed -r "s/[^ ]+ +([0-9]+).*$/\1/g" <<<"$line")"
    if [[ ! -z "$line" ]]; then
        echo "$ok,$name,$url,$ppid,$port,$innginx"
        if [[ -z "$quiet" ]]; then
            echo "API $name ($url) is running as PID $ppid and listening on port $port." 1>&2
        fi
    else
        echo "$ok,$name,$url,,,$innginx"
        if [[ -z "$quiet" ]]; then 
            echo "API $name ($url) is NOT running." 1>&2
            if [ "$ok" != "OK" ]; then
                echo "WARNING: API $name does not appear to be deployed correctly." 1>&2
                echo "         It is advisable to undeploy/delete and then redeploy $name." 1>&2
            fi
        fi
    fi

    cd $origdir
}

if [[ -z "$1" ]]; then
    # echo "api_name,base_url,process,local_port" 1>&2
    # Find and print status of all deployed APIs
    validapis=""
    for dir in $scriptdir/*/; do
        getstatus $dir -q
        if [[ -z "$validapis" ]]; then
            validapis="$(basename "$dir")"
        else
            validapis="$validapis|$(basename "$dir")"
        fi
    done
    # Check for running APIs that do NOT have a folder (should not exist)
    apispath="$(cd $fullpath/.. && pwd)"
    #ps -ef | grep -v grep | grep -E "$apispath/($validapis)/\.venv" 1>&2
    tput setaf 1
    ps -ef | grep -v grep | grep "$apispath/.*/\.venv" | grep -vE "$apispath/($validapis)/\.venv" 1>&2
    if [ $? == 0 ]; then
        echo "" 1>&2
        echo "WARNING: There are rogue APIs running (which listen to a port but don't have a deployed directory)." 1>&2
        echo "         See 'ps' output above these lines for details." 1>&2
    fi
    tput sgr0
else
    getstatus "$1"
fi

