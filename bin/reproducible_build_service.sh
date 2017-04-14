#!/bin/sh

# Copyright © 2017 Holger Levsen (holger@layer-acht.org)

set -x

echo $0
echo $1
export

sleep 3

sleep 5m
exit 0

BUILD_ID=$1
BUILD_URL=https://jenkins.debian.net/userContent/build_service/$BUILD_ID

case $BUILD_ID in
	arm64_builder1)		NODE1=codethink-sled12-arm64	NODE2=codethink-sled15-arm64 ;;
	*)			echo "Sleeping 60min" 
				sleep 60m
				exit 0
				;;
esac

BS_BASE=/var/lib/jenkins/userContent/reproducible/debian/build_service
mkdir -p $BS_BASE

/srv/jenkins/bin/reproducible_build.sh $NODE1 $NODE2 >$BS_BASE/$BUILD_ID 2>&1

# <      h01ger> | we could still make the logs accessable to browsers
# <      h01ger> | and we need maintenance to cleanup the log files eventually
# <      h01ger> | and translate that yaml to crontab entries
# a logic for real build_ids to have several logs
