#!/bin/bash

set -u
set -e

# don't try to run on test system
if [ "$HOSTNAME" = "jenkins-test-vm" ] ; then
	echo "$(date -u) - running on $HOSTNAME, exiting successfully and cleanly immediatly."
	exit 0
fi

# real start
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
  odxu4-armhf-rb.debian.net)
    PORT=2229
    ;;
  wbd0-armhf-rb.debian.net)
    PORT=2223
    ;;
  rpi2b-armhf-rb.debian.net)
    PORT=2230
    ;;
  rpi2c-armhf-rb.debian.net)
    PORT=2235
    ;;
  odxu4b-armhf-rb.debian.net)
    PORT=2232
    ;;
  odxu4c-armhf-rb.debian.net)
    PORT=2233
    ;;
  ff2a-armhf-rb.debian.net)
    PORT=2234
    ;;
  ff2b-armhf-rb.debian.net)
    PORT=2237
    ;;
  opi2a-armhf-rb.debian.net)
    PORT=2236
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

# pseudo job used to cleanup nodes
if [ "$JOB_NAME" = "cleanup_nodes" ] ; then
	   PARAMS="$PARAMS $@"
fi

#
# main
#
set +e
ssh -o "BatchMode = yes" -p $PORT $NODE_NAME /bin/true
RESULT=$?
# abort job if host is down
if [ $RESULT -ne 0 ] ; then
	echo "$(date -u) - $NODE_NAME seems to be down, sleeping 15min before aborting this job."
	sleep 15m
	exec /srv/jenkins/bin/abort.sh
fi
set -e
# finally
exec ssh -o "BatchMode = yes" -p $PORT $NODE_NAME "$PARAMS"

