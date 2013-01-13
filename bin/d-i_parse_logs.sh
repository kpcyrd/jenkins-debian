#!/bin/bash

# Copyright 2012, 2013 Holger Levsen <holger@layer-acht.org>
# released under the GPLv=2

if [ "$1" == "" ] ; then
	echo "need at least one URL to act on"
	echo '# $1 = URL'
	exit 1
fi

#
# convert params to variables
#
URL=$1

#
# default settings
#
#set -x
set -e
export LC_ALL=C
export http_proxy="http://localhost:3128"

TMPFILE=$(mktemp)
curl $URL > $TMPFILE
if [ $(grep -c failed $TMPFILE 2>/dev/null ) -gt 1 ] ; then 
	figlet Warning:
	figlet failed builds:
	for FILE in $(grep failed $TMPFILE | awk '{print $2}' FS=href= | cut -d '"' -f2) ; do
		echo Warning: $FILE failed
	done
else
	figlet ok
fi
echo
echo Check $1 yourself
echo

sed -i -s 's#<img src="#<img src="http://d-i.debian.org/daily-images/#g' $TMPFILE
mv $TMPFILE $(basename $URL)
