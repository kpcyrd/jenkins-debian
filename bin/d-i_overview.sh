#!/bin/bash

# Copyright 2014 Holger Levsen <holger@layer-acht.org>
# released under the GPLv=2

DEBUG=false
. /srv/jenkins/bin/common-functions.sh
common_init "$@"

# convert param to variables
if [ "$1" == "" ] ; then
	echo "need an Archicture to act on"
	exit 1
fi
ARCH=$1
URL=http://d-i.debian.org/daily-images/daily-build-overview.html

# randomize start times slightly
SLEEP=$(shuf -i 1-10 -n 1)
sleep 0.$SLEEP

TMPFILE=$(mktemp)
MISSING=$(mktemp)
FAILED=$(mktemp)
CLEAN=true

curl -s -S $URL -o $TMPFILE
echo "Checking $URL for build issues on $ARCH."

# http://anonscm.debian.org/viewvc/d-i/trunk/scripts/daily-build-overview?view=markup is used to generate the HTML
awk '/ul id="missingarchs/,/<\/ul>/' $TMPFILE > $MISSING
awk '/ul id="failedarchs/,/<\/ul>/' $TMPFILE > $FAILED
if grep -q "<li><a href=\"#$ARCH\"" $MISSING ; then
	echo "Warning: Build for $ARCH is missing - check $URL#$ARCH"
	CLEAN=false
fi
if grep -q "<li><a href=\"#$ARCH\"" $FAILED ; then
	echo "Failure: Build for $ARCH failed - check $URL#$ARCH"
	CLEAN=false
fi

if $CLEAN ; then
	echo "None found."
fi
echo

rm $TMPFILE $FAILED $MISSING
if ! $CLEAN ; then
	exit 1
fi
