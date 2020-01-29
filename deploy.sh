#!/usr/bin/bash
set -e

if [ ! -f "$1" ]; then
    echo "Could not find file named '$1'"
    exit 1
fi

file=$(basename "$1")
name=$(basename -s .zip $1)
directory=$(dirname "$1")
origdir=$(pwd)
cd $directory

echo "Extracting $1 to $name/..."
unzip $file -d $name

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
    exit 2
fi

echo "Installing Python requirements..."
python3 -m pip install --upgrade --no-index --find-links $name/wheels/ -r $name/LAUNCHPAD_REQ.txt

deactivate

#################
# TODO: COMMANDS HERE TO REGISTER API SOMEWHERE (GUNICORN/NGINX/....)
# use (and adapt) "./run.sh <apifolder>" to actually start an api
#################

cd $origdir

echo "Sucessfully deployed API $name"
