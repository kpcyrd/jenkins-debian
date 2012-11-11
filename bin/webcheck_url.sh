#!/bin/bash

# Copyright 2012 Holger Levsen <holger@layer-acht.org>
# released under the GPLv=2

# $1 = URL

if [ "$1" == "" ] ; then
	echo "need at least one URL to act on"
	echo '# $1 = URL'
	exit 1
fi

set -x
set -e
export LC_ALL=C
export http_proxy="http://localhost:3128"

#
# Don't use --continue on first run
#
if [ ! -e webcheck.dat ] ; then
	PARAMS=""
else
	PARAMS="-c -f"
fi

#
# if $1 ends with / then run webcheck with -b
#
if [ "${1: -1}" = "/" ] ; then
	PARAMS="$PARAMS -b"
fi

#
# $2 can only by used to ignore patterns atm
#
if [ "$2" != "" ] ; then
	PARAMS="$PARAMS $(for i in $2 ; do echo -n " -y $i" ; done)"
fi

#
# ignore a a lot more patterns (=all translations) when checking www.debian.org
#
if [ "${2:0-21}" = "http://www.debian.org" ] ; then
	TRANSLATIONS=$(curl www.debian.org 2>/dev/null|grep index|grep lang=|cut -d "." -f2)
	for LANG in $TRANSLATIONS ; do
		PARAMS="$PARAMS -y $LANG.html"
	done
fi

#
# actually run webcheck
#
webcheck $1 $PARAMS
