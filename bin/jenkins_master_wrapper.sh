#!/bin/bash

set -u
set -e
PARAMS="$JOB_NAME"

# these nodes also need to be listed in bin/reproducible_common.sh where they define $BUILD_NODES
case "$NODE_NAME" in
  bpi0-armhf-rb.debian.net)
    PORT=2222
    ;;
  hb0-armhf-rb.debian.net)
    PORT=2224
    ;;
  wbq0-armhf-rb.debian.net)
    PORT=2225
    ;;
  cbxi4pro0-armhf-rb.debian.net)
    PORT=2226
    ;;
  profitbricks-build?-amd64.debian.net)
    PORT=22
    if [[ "$JOB_NAME" =~ rebootstrap_.* ]] ; then
	   PARAMS="$PARAMS $@"
    fi
    ;;
  *)
    echo >&2 "Unknown node $NODE_NAME."
    exit 1
esac

#
# main
#
set +e
ssh -p $PORT $NODE_NAME /bin/true
RESULT=$?
# abort job if host is down
if [ $RESULT -ne 0 ] ; then
	echo "$(date -u) - $NODE_NAME seems to be down, sleeping 15min before aborting this job."
	sleep 15m
	exec /srv/jenkins/bin/abort.sh
fi
set -e
# finally
exec ssh -p $PORT $NODE_NAME "$PARAMS"

