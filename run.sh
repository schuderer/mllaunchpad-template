#!/usr/bin/bash

if [ ! -d "$1" ]; then
    echo "Could not find API directory named '$1'"
    exit 1
fi

name=$(basename "$1")
directory=$1
origdir=$(pwd)
cd $directory


echo "Activating Python environment for API $name..."
source .venv/bin/activate

gunicorn --workers 4 --bind 127.0.0.1:5000 mllaunchpad.wsgi

deactivate
cd $origdir
