#!/usr/bin/bash
set -e

if [ ! -f "$1" ]; then
    echo "Could not find file named '$1'"
    exit 1
fi

registry=deployed_apis.txt
file=$(basename "$1")
name=$(basename -s .zip $1)
api_name=$(cut -d'_' -f1 <<<"$name")
api_version=$(cut -d'_' -f2 <<<"$name")
api_major=$(cut -d'.' -f1 <<<"$api_version")
api_root="$api_name/v$api_major/"
directory=$(dirname "$1")
origdir=$(pwd)
cd $directory

if [ -d "$name" ]; then
    echo "An API named '$name' is already deployed (directory exists). Aborting deployment."
    exit 2
fi

if [ -f "$registry" ]; then
    set +e
    grep -qF "$name" "$registry"
    if [[ $? == 0 ]]; then
        echo "An API named '$name' is already deployed (listed in $registry)."
        echo "Aborting deployment."
        exit 4
    fi
    set -e
fi

echo "Extracting $1 to $name/..."
unzip $file -d $name

# subshell to emulate try catch to be able to remove the half-deployed api
set +e
(
set -e
mapfile -t req_files <"$name/LAUNCHPAD_REQ_FILES.txt"
for req_file in "${req_files[@]}"
do
  if [ ! -e "$req_file" ]; then
      echo "The required resource '$req_file' has not been found. Aborting deployment."
      exit 5
  fi
done

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
    echo "Local Python version is $version, artifact built for version $req_version. Aborting deployment."
    exit 3
fi

echo "Installing Python requirements..."
python3 -m pip install --upgrade --no-index --find-links $name/wheels/ -r $name/LAUNCHPAD_REQ.txt

deactivate

echo "Registering API in $registry"
echo "$name,$api_root" >>$registry

echo "Successfully deployed API $name"
)
if [[ $? != 0 ]]; then
    echo "An error occurred. Removing the api directory '$name'..."
    rm -rf "$name"
fi

cd $origdir
