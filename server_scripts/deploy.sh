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

# Subshell emulating try-catch. In order to be able to remove the half-deployed api on failure
set +e
(
set -e
echo "Extracting $1 to $name/..."
unzip $file -d $name

echo "Checking required resources..."
mapfile -t req_files <"$name/LAUNCHPAD_REQ_FILES.txt"
for req_file in "${req_files[@]}"
do
  full_req_file="$name/$req_file"
  if [ ! -e "$full_req_file" ]; then
      echo "The required resource '$full_req_file' has not been found. Aborting deployment."
      exit 5
  fi
  echo "Resource '$full_req_file' found"
done

mypython="$(cat PYTHON.txt)"
echo "Using Python interpreter at $mypython (from PYTHON.txt)"

echo "Creating Python virtual environment..."
# Use the global site-packages pip instead of installing the default one of this python in the venv
#$mypython -m venv --clear --system-site-packages $name/.venv
$mypython -m venv --clear $name/.venv

source $name/.venv/bin/activate
interpreter=$name/.venv/bin/python3
which python3
python3 --version

echo "Checking Python version..."
version="$(python3 -c 'import sys;print(str(sys.version_info[0])+str(sys.version_info[1]))')"
req_version="$(<$name/LAUNCHPAD_REQ_PYTHON.txt)"
if [[ "$version" == "$req_version" ]]; then
    echo "OK."
else
    echo "Local Python version is $version, artifact built for version $req_version. Aborting deployment."
    exit 3
fi

echo "Installing Python requirements..."
python3 -m pip install --upgrade --no-index --find-links $name/wheels/ -r $name/LAUNCHPAD_REQ.txt
rm -rf $name/wheels

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
