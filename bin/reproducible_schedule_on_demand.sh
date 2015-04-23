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
SUITE="$1"
shift
if [ "$SUITE" = "sid" ] ; then
	echo "WARNING: sid has been renamed to unstable."
	SUITE=unstable
fi

case "$1" in
	"artifacts")
		ARTIFACTS=1
		NOTIFY=true
		shift
		printf "\nThe artifacts of the build(s) will be saved to the location mentioned at the end of the build log(s).\n\n"
		;;
	"notify")
		ARTIFACTS=0
		NOTIFY=true
		shift
		printf "\nThe IRC channel will be notify once the build(s) finished.\n\n"
		;;
	*)
		ARTIFACTS=0
		NOTIFY=''
		;;
esac

CANDIDATES="$@"
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
elif $NOTIFY ; then
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
