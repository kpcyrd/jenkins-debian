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
export LANG=C
export http_proxy="http://localhost:3128"

PARAMS="-c -f"
if [ "$2" != "" ] ; then
	PARAMS=$(for i in $2 ; do echo -n " -y $i" ; done)
fi
webcheck $1 $PARAMS
