#!/bin/bash

# Copyright © 2017 Holger Levsen (holger@layer-acht.org)
# released under the GPLv=2

# normally defined by jenkins
JENKINS_URL=https://jenkins.debian.net

DEBUG=false
. /srv/jenkins/bin/common-functions.sh
common_init "$@"

# common code defining db access
. /srv/jenkins/bin/reproducible_common.sh

set -e
set -x
# sleep 1-23 secs to randomize start times
/bin/sleep $(echo "scale=1 ; $(shuf -i 1-230 -n 1)/10" | bc )

BUILD_BASE=/var/lib/jenkins/userContent/reproducible/debian/build_service/$1
OLD_ID=$(ls -1rt $BUILD_BASE|grep -v latest|sort -n|tail -1)
let BUILD_ID=OLD_ID+1
mkdir -p $BUILD_BASE/$BUILD_ID
ln -sf $BUILD_ID $BUILD_BASE/latest

export BUILD_URL=https://jenkins.debian.net/userContent/build_service/$1/
export BUILD_ID=$BUILD_ID
export JOB_NAME="reproducible_builder_$1"

case $1 in
	arm64_1)	NODE1=codethink-sled12-arm64	NODE2=codethink-sled15-arm64 ;;
	i386_1)		NODE1=profitbricks-build2-i386	NODE2=profitbricks-build6-i386 ;;
	i386_2)		NODE1=profitbricks-build6-i386	NODE2=profitbricks-build2-i386 ;;
	i386_3)		NODE1=profitbricks-build2-i386	NODE2=profitbricks-build16-i386 ;;
	i386_4)		NODE1=profitbricks-build16-i386	NODE2=profitbricks-build2-i386 ;;
	i386_5)		NODE1=profitbricks-build12-i386	NODE2=profitbricks-build6-i386 ;;
	i386_6)		NODE1=profitbricks-build6-i386	NODE2=profitbricks-build12-i386 ;;
	i386_7)		NODE1=profitbricks-build12-i386	NODE2=profitbricks-build16-i386 ;;
	i386_8)		NODE1=profitbricks-build16-i386	NODE2=profitbricks-build12-i386 ;;
	i386_9)		NODE1=profitbricks-build2-i386	NODE2=profitbricks-build6-i386 ;;
	i386_10)	NODE1=profitbricks-build6-i386	NODE2=profitbricks-build2-i386 ;;
	i386_11)	NODE1=profitbricks-build2-i386	NODE2=profitbricks-build16-i386 ;;
	i386_12)	NODE1=profitbricks-build16-i386	NODE2=profitbricks-build2-i386 ;;
	i386_13)	NODE1=profitbricks-build12-i386	NODE2=profitbricks-build6-i386 ;;
	i386_14)	NODE1=profitbricks-build6-i386	NODE2=profitbricks-build12-i386 ;;
	i386_15)	NODE1=profitbricks-build12-i386	NODE2=profitbricks-build16-i386 ;;
	i386_16)	NODE1=profitbricks-build16-i386	NODE2=profitbricks-build12-i386 ;;
	i386_17)	NODE1=profitbricks-build2-i386	NODE2=profitbricks-build6-i386 ;;
	i386_18)	NODE1=profitbricks-build6-i386	NODE2=profitbricks-build2-i386 ;;
	i386_19)	NODE1=profitbricks-build2-i386	NODE2=profitbricks-build16-i386 ;;
	i386_20)	NODE1=profitbricks-build16-i386	NODE2=profitbricks-build2-i386 ;;
	i386_21)	NODE1=profitbricks-build12-i386	NODE2=profitbricks-build6-i386 ;;
	i386_22)	NODE1=profitbricks-build6-i386	NODE2=profitbricks-build12-i386 ;;
	i386_23)	NODE1=profitbricks-build12-i386	NODE2=profitbricks-build16-i386 ;;
	i386_24)	NODE1=profitbricks-build16-i386	NODE2=profitbricks-build12-i386 ;;
	*)		echo "Sleeping 60min" 
			sleep 60m
			exit 0
			;;
esac

/srv/jenkins/bin/reproducible_build.sh $NODE1 $NODE2 >$BUILD_BASE/$BUILD_ID/console.log 2>&1

# < h01ger> | logs should auto display in browser like with jenkins… (long-polling, meta-refresh, something)
# < h01ger> | and we need maintenance to cleanup the log files eventually
# < h01ger> | and translate that yaml to crontab entries, starting with i386


