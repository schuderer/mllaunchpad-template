#!/usr/bin/bash

port=8000

usage() {
    echo "Usage: $0 [-n <number_of_ports, default: 1>]" 1>&2
    echo "Finds and outputs available port numbers, starting from port $port." 1>&2
    echo "ATTENTION: If you need many free ports, use the -n option." 1>&2
    echo "           Don't get single ports and start services on them in a tight loop or you will run into duplicates." 1>&2
    echo "Options: -n <number_of_ports>  Outputs this many unique free port numbers (default: 1, max: 1000)." 1>&2
    echo "         -h                    Show this message and exit." 1>&2
}

while getopts ":nh" o; do
    case $o in
        p)
            howmany=$OPTARG
            ;;
        h)
            usage
            exit 0
            ;;
    esac
done

while [ $port != 9000 ]; do
   ss -ln | grep -q ":$port "
   if [ $? != 0 ]; then
      echo $port
      let howmany--
      if (( $howmany <= 0 )); then
          exit 0
      fi
   fi
   let port++
done

echo "ERROR: Could not find a free port. Aborting." 1>&2
echo "Type '$0 -h' for help." 1>&2
exit 1

