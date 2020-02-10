#!/usr/bin/bash
set -e

if [ -z "$1" ]; then
    echo "Missing argument: API name."
    exit 1
fi

registry=deployed_apis.txt
name=$(basename -s .zip $1)
directory=$(dirname "$1")
origdir=$(pwd)
cd $directory

if [ ! -d "$name" ]; then
    echo "No deployed API named '$name' to undeploy (directory not found). Aborting."
    exit 2
fi

if [ -f "$registry" ]; then
    set +e
    grep -qF "$name" "$registry"
    if [[ $? == 1 ]]; then
        echo "No deployed API named '$name' to undeploy (not listed in $registry)."
        echo "Aborting."
        exit 4
    fi
    set -e
fi

echo "Removing directory $name/..."
rm -rf $name

echo "Unregistering API from $registry"
line=$(grep -F "$name" "$registry")
echo "Line to remove: '$line'"
grep -Fv "$name" "$registry" > mytempfile
mv mytempfile "$registry"

cd $origdir

echo "Sucessfully undeployed API $name"
