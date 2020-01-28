#!/usr/bin/bash

name="$(basename -s .zip $1)"

echo "Extracting $1 to $name/..."

unzip $1 -d $name

echo "Creating Python virtual environment..."
python3 -m venv --clear $name/.venv

source $name/.venv/bin/activate
interpreter=$name/.venv/bin/python3
which python3
python3 --version

echo "Checking Python version..."
version="$(python -c 'import sys;print(str(sys.version_info[0])+str(sys.version_info[1]))')"
req_version="$(<$name/LAUNCHPAD_REQ_PYTHON.txt)"
if [[ "$version" == "$req_version" ]]; then
    echo "OK."
else
    echo "Local Python version is $version, artifact built for version $req_version. Aborting."
    exit 1
fi

echo "Installing Python requirements..."
python3 -m pip install --upgrade --no-index --find-links $name/wheels/ -r $name/LAUNCHPAD_REQ.txt

deactivate
