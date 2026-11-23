#!/bin/sh

#set -e
#nginx -t
#nginx
CA=/home/ots/ots/ca
FILES="$CA/ca.pem $CA/certs/opentakserver/opentakserver.pem $CA/certs/opentakserver/opentakserver.nopass.key"

(
  i=0
  for f in $FILES; do
    while [ ! -s "$f" ]; do
      i=$((i+1))
      if [ $i -ge 300 ]; then
        echo "start-nginx: gave up waiting for $f" >&2
        exit 1
      fi
      sleep 2
    done
  done
  sleep 2   # let OTS finish writing the CA files
  /usr/sbin/nginx -t && /usr/sbin/nginx
) &

exec /home/ots/entrypoint.sh "$@"
