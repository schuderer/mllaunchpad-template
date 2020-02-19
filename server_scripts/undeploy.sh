#!/usr/bin/bash
set -e

if [ -z "$1" ]; then
    echo "Missing argument: API name."
    exit 1
fi

name=$(basename -s .zip $1)
directory=$(dirname "$1")
origdir=$(pwd)
cd $directory

if [ ! -d "$name" ]; then
    echo "No deployed API named '$name' to undeploy (directory not found). Aborting."
    exit 2
fi

runinfo="$(./status.sh $name)"
ppid="$(cut -d, -f4 <<<"$runinfo")"

if [[ ! -z "$ppid" ]]; then
    echo "Cannot undeploy a running API. API $name is running as process $ppid. Aborting."
    exit 3
fi


echo "Removing directory $name/..."
rm -rf $name

cd $origdir

echo "Sucessfully undeployed API $name"
