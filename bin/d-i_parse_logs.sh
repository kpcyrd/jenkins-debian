#!/bin/bash

# Copyright 2012-2014 Holger Levsen <holger@layer-acht.org>
# released under the GPLv=2

DEBUG=false
. /srv/jenkins/bin/common-functions.sh
common_init "$@"

# convert param to variables
if [ "$1" == "" ] ; then
	echo "need at least one URL to act on"
	echo '# $1 = URL'
	exit 1
fi
URL=$1

TMPFILE=$(mktemp)
curl $URL > $TMPFILE
if [ $(grep -c failed $TMPFILE 2>/dev/null ) -gt 1 ] ; then 
	figlet Warning:
	figlet failed builds:
	for FILE in $(grep failed $TMPFILE | awk '{print $2}' FS=href= | cut -d '"' -f2) ; do
		echo Warning: $FILE failed
	done
elif [ $(grep buildd $TMPFILE 2>/dev/null|grep -v "$(date +'%b %d')"|grep -v "$(date --date yesterday +'%b %d')"|grep -v "See also"|wc -l ) -gt 0 ] ; then
	echo "Warning: outdated builds:"
	figlet outdated builds
	grep buildd $TMPFILE 2>/dev/null|grep -v "$(date +'%b %d')"| grep -v "$(date --date yesterday +'%b %d')" |grep -v "See also"
else
	figlet ok
fi
echo
echo Check $1 yourself
echo

sed -i -s 's#<img src="#<img src="http://d-i.debian.org/daily-images/#g' $TMPFILE
mv $TMPFILE $(basename $URL)
