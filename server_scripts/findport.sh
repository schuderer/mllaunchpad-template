#!/usr/bin/bash

port=8000
howmany=1
if [ ! -z $1 ]; then
    howmany=$1
fi

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

echo "Could not find a free port. Aborting." >&2
exit 1

