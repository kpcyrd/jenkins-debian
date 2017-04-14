#!/bin/sh

# Copyright © 2017 Holger Levsen (holger@layer-acht.org)

set -x

echo $0
echo $1
export

sleep 3

BUILD_ID=$1
BUILD_URL=https://jenkins.debian.net/userContent/build_service/$BUILD_ID

case $BUILD_ID in
	arm64_builder1)		NODE1=codethink-sled12-arm64
				NODE2=codethink-sled15-arm64
				;;
	*)			echo "Sleeping 60min" 
				sleep 60m
				exit 0
				;;
esac

BS_BASE=/var/lib/jenkins/userContent/reproducible/debian/build_service
mkdir -p $BS_BASE

/srv/jenkins/bin/reproducible_build.sh $NODE1 $NODE2 >$BS_BASE/$BUILD_ID 2>&1

#script translates "arm64 builder12" to "arm64 builder12 sled3 sled 4"
# <      h01ger> | but then its really simple: have a script, jenkins_build_cron_runner.sh or such, and start this with 4 params, eg, arm64, builder_12, codethink_sled11, codethink_sled14. the cron_runner script simple needs to set some variables like jenkins would do, redirect output 
#   to a directory which is accessable to the webserver and run reproducible_build.sh. voila.
# <      h01ger> | we could still make the logs accessable to browsers
# <      h01ger> | and we need maintenance to cleanup the log files eventually
# <      h01ger> | and translate that yaml to crontab entries

