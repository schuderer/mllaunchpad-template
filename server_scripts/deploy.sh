#!/usr/bin/bash
set -e

scriptdir="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"

usage() {
    echo "Usage: $0 [-a] <api_artifact>" 1>&2
    echo "Deploys the zipped API artifact <api_artifact>." 1>&2
    echo "Options: -a     Automatically start the API (in gunicorn and behind nginx)." 1>&2
    echo "                Completely new APIs will be deployed next to existing APIs" 1>&2
    echo "                New major versions will be deployed next to the current version(s)." 1>&2
    echo "                New minor or patch versions will REPLACE the current version (of the same major version)." 1>&2
    echo "         -h     Show this message and exit." 1>&2
}

autorun=false
while getopts ":ah" o; do
    case $o in
        a)
            autorun=true
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
echo "$(date) Deploying $@ with autorun=$autorun"

if [ ! -f "$1" ]; then
    echo "ERROR: Could not find file named '$1'" 1>&2
    echo "Type '$0 -h' for help." 1>&2
    exit 1
fi

file=$(basename "$1")
name=$(basename -s .zip $1)
base_dir=$(dirname "$1")
origdir=$(pwd)
cd $base_dir

if [ -d "$name" ]; then
    echo "ERROR: An API named '$name' is already deployed (directory exists). Aborting deployment." 1>&2
    echo "Type '$0 -h' for help." 1>&2
    exit 2
fi

# Subshell emulating try-catch. In order to be able to remove the half-deployed api on failure
set +e
(
set -e
echo "Extracting $1 to $name/..." 1>&2
unzip $file -d $name/

# The nginx user must be able to access this directory
chmod o+rx $name/

# Remove any stray world-write bits inherited from the zip file
chmod o-w -R $name/

echo "Checking required resources..." 1>&2
mapfile -t req_files <"$name/LAUNCHPAD_REQ_FILES.txt"
for req_file in "${req_files[@]}"
do
  full_req_file="$name/$req_file"
  if [ ! -e "$full_req_file" ]; then
      echo "ERROR: The required resource '$full_req_file' has not been found. Aborting deployment." 1>&2
      echo "Type '$0 -h' for help." 1>&2
      exit 5
  fi
  echo "Resource '$full_req_file' found" 1>&2
done

mypython="$(cat PYTHON.txt)"
echo "Using Python interpreter at $mypython (from PYTHON.txt)" 1>&2

echo "Creating Python virtual environment..." 1>&2
# Use the global site-packages pip instead of installing the default one of this python in the venv
#$mypython -m venv --clear --system-site-packages $name/.venv
$mypython -m venv --clear $name/.venv

source $name/.venv/bin/activate
interpreter=$name/.venv/bin/python3
which python3
python3 --version

echo "Checking Python version..." 1>&2
version="$(python3 -c 'import sys;print(str(sys.version_info[0])+str(sys.version_info[1]))')"
req_version="$(<$name/LAUNCHPAD_REQ_PYTHON.txt)"
if [[ "$version" == "$req_version" ]]; then
    echo "OK." 1>&2
else
    echo "ERROR: Local Python version is $version, artifact built for version $req_version. Aborting deployment." 1>&2
    echo "Type '$0 -h' for help." 1>&2
    exit 3
fi

echo "Installing Python requirements..." 1>&2
python3 -m pip install --upgrade --no-index --find-links $name/wheels/ -r $name/LAUNCHPAD_REQ.txt
rm -rf $name/wheels/

deactivate

echo "Successfully deployed API $name" 1>&2
)
errcode=$?
if [[ $errcode != 0 ]]; then
    echo "An error occurred. Removing the api directory '$name'..." 1>&2
    rm -rf "$name/"
    echo "Type '$0 -h' for help." 1>&2
    exit $errcode
else
    cd $scriptdir
    if [[ "$autorun" == "true" ]]; then
        echo "Attempting to take the API $name live automatically" 1>&2
        incompat="$(cut -d. -f1 <<<$name)"   # e.g. iris_0
        otherinfo="$(./status.sh | grep "$incompat" | grep -v "$name")"
        othername="$(cut -d, -f2 <<<"$otherinfo")"
        if [ ! -z "$othername" ]; then
            echo "Removing the incompatible API $othername from nginx config..." 1>&2
            ./stop.sh -n $othername
        fi
        ./run.sh -a $name
        set +e
        sudo nginx -t
        if [[ $? != 0 ]]; then
            echo "ERROR: Nginx does not seem to like the current configuration. Use 'sudo nginx -T' to examine the nginx config." 1>&2
            echo "Killing the API process..." 1>&2
            ./stop.sh -n $name
            ./stop.sh -k $name
            exit 4
        fi
        set -e
        sudo systemctl reload nginx
        if [ ! -z "$othername" ]; then
            echo "Stopping the incompatible API $othername's process..." 1>&2
            ./stop.sh -k $othername
            sleep 1
        fi
        echo "The API $name is now live and being served via nginx." 1>&2
    fi
fi
) 2>&1 | tee -a "$(cat LOGPATH.txt)/deploy.log"

echo "[Use run.sh/stop.sh to start/stop APIs and status.sh to see the status of deployed APIs.]" 1>&2
