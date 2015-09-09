#!/bin/bash

# Copyright 2015 Holger Levsen <holger@layer-acht.org>
# released under the GPLv=2

set -e
# common code defining BUILD_ENV_VARS
. /srv/jenkins/bin/reproducible_common.sh

# these variables also need to be in bin/reproducible_common.sh where they define $BUILD_ENV_VARS (see right below)
ARCH=$(dpkg --print-architecture)
NUM_CPU=$(grep -c '^processor' /proc/cpuinfo)
CPU_MODEL=$(cat /proc/cpuinfo |grep "model name"|head -1|cut -d ":" -f2|xargs echo)
DATETIME=$(date +'%Y-%m-%d %H:%M %Z')

for i in $BUILD_ENV_VARS ; do
	echo "$i=${!i}"
done
