#!/bin/bash

# Copyright 2012 Holger Levsen <holger@layer-acht.org>
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
PATTERNS=$2

#
# default settings
#
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
# if $URL ends with / then run webcheck with -b
#
if [ "${URL: -1}" = "/" ] ; then
	PARAMS="$PARAMS -b"
fi

#
# ignore some extra patterns (=all translations) when checking www.debian.org
#
if [ "${URL:0:21}" = "http://www.debian.org" ] ; then
	TRANSLATIONS=$(curl www.debian.org 2>/dev/null|grep index|grep lang=|cut -d "." -f2)
	for LANG in $TRANSLATIONS pt_BR zh_CN zh_HK zh_TW ; do
		PARAMS="$PARAMS -y \.${LANG}\.html -y html\.${LANG} -y \.${LANG}\.txt -y \${LANG}\.pdf"
	done
	
fi

#
# $PATTERNS can only be used to ignore patterns atm
#
if [ "$PATTERNS" != "" ] ; then
	PARAMS="$PARAMS $(for i in $PATTERNS ; do echo -n " -y $i" ; done)"
fi

#
# actually run webcheck
#
webcheck $URL $PARAMS
