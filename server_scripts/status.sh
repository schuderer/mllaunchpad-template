#!/usr/bin/bash

scriptdir="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"


getstatus() {
    if [ ! -d "$1" ]; then
        echo "Could not find API directory named '$1'"
        exit 1
    fi
    if [[ ! -z "$2" ]]; then
        quiet="1"
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
    url="$(cat $fullpath/LAUNCHPAD_BASE_URL.txt)"
    # ps's H option prints hierarchically, with parent processes before child processes
    # so we can just take the first matching line, which will be the parent process.
    line="$(ps -efH | grep -v grep | grep -m 1 "$fullpath/\.venv")"
    port="$(sed -r "s/^.*127.0.0.1:([[:digit:]]+).*$/\1/g" <<<"$line")"
    ppid="$(sed -r "s/[^ ]+ +([0-9]+).*$/\1/g" <<<"$line")"
    if [[ ! -z "$line" ]]; then
        echo "$ok,$name,$url,$ppid,$port"
        if [[ -z "$quiet" ]]; then
            echo "API $name ($url) is running as PID $ppid and listening on port $port." >&2
        fi
    else
        echo "$ok,$name,$url,,"
        if [[ -z "$quiet" ]]; then 
            echo "API $name ($url) is NOT running." >&2
            if [ "$ok" != "OK" ]; then
                echo "WARNING: API $name does not appear to be deployed correctly." >&2
                echo "         It is advisable to undeploy/delete and then redeploy $name." >&2
            fi
        fi
    fi

    cd $origdir
}

if [[ -z "$1" ]]; then
    # echo "api name,base url,process,port on 127.0.0.1"
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
    #ps -ef | grep -v grep | grep -E "$apispath/($validapis)/\.venv" >&2
    tput setaf 1
    ps -ef | grep -v grep | grep "$apispath/.*/\.venv" | grep -vE "$apispath/($validapis)/\.venv" >&2
    if [ $? == 0 ]; then
        echo ""
        echo "WARNING: There are rogue APIs running (which listen to a port but don't have a deployed directory)." >&2
        echo "         See 'ps' output above these lines for details." >&2
    fi
    tput sgr0
else
    getstatus "$1"
fi

