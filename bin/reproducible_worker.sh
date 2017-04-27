#!/bin/bash

# Copyright © 2017 Holger Levsen (holger@layer-acht.org)
# released under the GPLv=2

set -e

WORKER_NAME=$1
NODE1=$2
NODE2=$3

# normally defined by jenkins and used by reproducible_common.sh
JENKINS_URL=https://jenkins.debian.net

DEBUG=false
. /srv/jenkins/bin/common-functions.sh
common_init "$@"

# common code defining db access
. /srv/jenkins/bin/reproducible_common.sh

# endless loop
while true ; do
	#
	# check if we really should be running
	#
	RUNNING=$(ps fax|grep -v grep|grep "$0 $1 ")
	if [ -z "$RUNNING" ] ; then
		echo "$(date --utc) - '$0 $1' already running, thus stopping this."
		break
	fi
	SERVICE="reproducible_build@startup.service"
	RUNNING=$(systemctl show $SERVICE|grep ^SubState|cut -d "=" -f2)
	if [ "$RUNNING" != "running" ] ; then
		echo "$(date --utc) - '$SERVICE' not running, thus stopping this."
		break
	fi

	# sleep up to 2.3 seconds (additionally to the random sleep reproducible_build.sh does anyway)
	/bin/sleep $(echo "scale=1 ; $(shuf -i 1-23 -n 1)/10" | bc )

	#
	# increment BUILD_ID
	#
	BUILD_BASE=/var/lib/jenkins/userContent/reproducible/debian/build_service/$WORKER_NAME
	OLD_ID=$(ls -1rt $BUILD_BASE|egrep -v "(latest|worker.log)" |sort -n|tail -1)
	let BUILD_ID=OLD_ID+1
	mkdir -p $BUILD_BASE/$BUILD_ID
	rm -f $BUILD_BASE/latest
	ln -sf $BUILD_ID $BUILD_BASE/latest

	#
	# prepare variables for export
	#
	export BUILD_URL=https://jenkins.debian.net/userContent/build_service/$WORKER_NAME/$BUILD_ID/
	export BUILD_ID=$BUILD_ID
	export JOB_NAME="reproducible_builder_$WORKER_NAME"
	export

	#
	# actually run reproducible_build.sh
	#
	/srv/jenkins/bin/reproducible_build.sh $NODE1 $NODE2 >$BUILD_BASE/$BUILD_ID/console 2>&1
done
