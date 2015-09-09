#!/bin/bash

# Copyright 2015 Holger Levsen <holger@layer-acht.org>
# released under the GPLv=2

set -e

ARCH=$(dpkg --print-architecture)
NUM_CPU=$(grep -c '^processor' /proc/cpuinfo)
CPU_MODEL=$(cat /proc/cpuinfo |grep "model name"|head -1|cut -d ":" -f2|xargs echo)
DATETIME=$(date +'%Y-%m-%d %H:%M %Z')

for i in ARCH NUM_CPU CPU_MODEL DATETIME ; do
	echo "$i=${!i}"
done
