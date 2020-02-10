#!/usr/bin/bash

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
cd $directory


echo "Activating Python environment for API $name..."
source .venv/bin/activate

gunicorn --workers 4 --bind 127.0.0.1:$2 mllaunchpad.wsgi

deactivate
cd $origdir
