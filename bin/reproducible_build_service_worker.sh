#!/bin/bash

# Copyright © 2017 Holger Levsen (holger@layer-acht.org)
# released under the GPLv=2

# normally defined by jenkins
JENKINS_URL=https://jenkins.debian.net
set -e
set -x

WORKER_NAME=$1
NODE1=$2
NODE2=$3

DEBUG=false
. /srv/jenkins/bin/common-functions.sh
common_init "$@"

# common code defining db access
. /srv/jenkins/bin/reproducible_common.sh

while true ; do
	# TODO
	# - test here if the builder service is actually running…

	# sleep up to 2.3 seconds (additionally to the random sleep reproducible_build.sh does anyway)
	/bin/sleep $(echo "scale=1 ; $(shuf -i 1-23 -n 1)/10" | bc )

	BUILD_BASE=/var/lib/jenkins/userContent/reproducible/debian/build_service/$WORKER_NAME
	OLD_ID=$(ls -1rt $BUILD_BASE|egrep -v "(latest|worker.log)" |sort -n|tail -1)
	let BUILD_ID=OLD_ID+1
	mkdir -p $BUILD_BASE/$BUILD_ID
	rm -f $BUILD_BASE/latest
	ln -sf $BUILD_ID $BUILD_BASE/latest

	export BUILD_URL=https://jenkins.debian.net/userContent/build_service/$WORKER_NAME/
	export BUILD_ID=$BUILD_ID
	export JOB_NAME="reproducible_builder_$WORKER_NAME"
	export

	/srv/jenkins/bin/reproducible_build.sh $NODE1 $NODE2 >$BUILD_BASE/$BUILD_ID/console.log 2>&1
done


