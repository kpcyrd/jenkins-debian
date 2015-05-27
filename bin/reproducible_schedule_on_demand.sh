#!/bin/bash

# Copyright 2014 Holger Levsen <holger@layer-acht.org>
#         © 2015 Mattia Rizzolo <mattia@mapreri.org>
# released under the GPLv=2

DEBUG=false
. /srv/jenkins/bin/common-functions.sh
common_init "$@"

# common code defining db access
. /srv/jenkins/bin/reproducible_common.sh

#
# main
#
set +x
ARTIFACTS=0
NOTIFY=''
if [ "$1" = "--notify" ] ; then
	NOTIFY=true
	shift
elif [ "$1" = "--artifacts" ] ; then
	ARTIFACTS=1
	NOTIFY=true
fi
SUITE="$1"
shift
if [ "$SUITE" = "sid" ] ; then
	echo "WARNING: sid has been renamed to unstable."
	SUITE=unstable
fi

CANDIDATES="$@"
if [ ${#} -gt 50 ] && [ "$NOTIFY" = "true" ] ; then
	echo
	figlet "No."
	echo "Do not schedule more than 50 packages with notification. If you really really need to spam the IRC channel this much, use a loop to achieve that. Exiting."
	echo
	exit 1
fi
check_candidates
if [ ${#PACKAGE_IDS} -gt 256 ] ; then
	BLABLABLA="✂…"
fi
ACTION="manually rescheduled"
if [ -n "${BUILD_URL:-}" ] ; then
	ACTION="rescheduled by $BUILD_URL"
fi
MESSAGE="$TOTAL $PACKAGES_TXT $ACTION in $SUITE: ${PACKAGES_NAMES:0:256}$BLABLABLA"
if [ $ARTIFACTS -eq 1 ] ; then
	MESSAGE="$MESSAGE - artifacts will be preserved."
elif [ "$NOTIFY" = "true" ] ; then
	MESSAGE="$MESSAGE - notification once finished."
fi

# finally
schedule_packages $PACKAGE_IDS
echo
echo "$MESSAGE"
if [ -z "${BUILD_URL:-}" ] && [ $TOTAL -ne 0 ] ; then
	kgb-client --conf /srv/jenkins/kgb/debian-reproducible.conf --relay-msg "$MESSAGE"
fi
echo "============================================================================="
echo "The following $TOTAL source $PACKAGES_TXT $ACTION for $SUITE: $PACKAGES_NAMES"
echo "============================================================================="
echo
