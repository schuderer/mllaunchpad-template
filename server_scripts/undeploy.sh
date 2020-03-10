#!/usr/bin/bash
set -e

scriptdir="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"

usage() {
    echo "Usage: $0 [-f] <api_dir>" 1>&2;
    echo "Undeploys the API specified by <api_dir> (API must not be running)." 1>&2;
    echo "Options: -f    Force undeployment of running API. Shuts down running API, then undeploys." 1>&2;
    echo "         -h    Show this message and exit." 1>&2
}

force=false
while getopts ":fh" o; do
    case $o in
        f)
            force=true
            ;;
        h)
            usage
            exit 0
            ;;
    esac
done
shift $((OPTIND - 1 ))

(
echo "=============================================================="
echo "$(date) Undeploying $@ with force=$force"

if [ -z "$1" ]; then
    echo "ERROR: Missing argument: API name." 1>&2
    echo "Type '$0 -h' for help." 1>&2
    exit 1
fi

name=$(basename -s .zip $1)
qqbase_dir=$(dirname "$1")
origdir=$(pwd)
cd $scriptdir

if [ ! -d "$name" ]; then
    echo "ERROR: No deployed API named '$name' to undeploy (directory not found). Aborting." 1>&2
    echo "Type '$0 -h' for help." 1>&2
    exit 2
fi

runinfo="$(./status.sh $name)"
ppid="$(cut -d, -f4 <<<"$runinfo")"

if [[ ! -z "$ppid" ]]; then
    if [ "$force" == "true" ]; then
        echo "Option -f used. Shutting down running APIs." 1>&2
        ./stop.sh -n $name
        sudo systemctl reload nginx
        ./stop.sh -k $name
    else
        echo "ERROR: Cannot undeploy a running API. API $name is running as process $ppid. Aborting." 1>&2
        echo "Type '$0 -h' for help." 1>&2
        exit 3
    fi
fi


echo "Removing directory $name/..." 1>&2
rm -rf $name/

cd $origdir

echo "Sucessfully undeployed API $name" 1>&2
) 2>&1 | tee -a "$(cat LOGPATH.txt)/undeploy.log"

echo "[Use run.sh/stop.sh to start/stop APIs and status.sh to see the status of deployed APIs.]" 1>&2
