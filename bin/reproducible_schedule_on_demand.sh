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

ARTIFACTS=0
if [ $1 = "artifacts" ] ; then
	ARTIFACTS=1
	shift
	echo
	echo "The artifacts of these builds will be saved. Look at the build log for the link"
	echo
fi

CANDIDATES="$@"
check_candidates
if [ ${#PACKAGE_IDS} -gt 256 ] ; then
	BLABLABLA="..."
fi
ACTION="manually rescheduled"
if [ -n "${BUILD_URL:-}" ] ; then
	ACTION="rescheduled by $BUILD_URL"
fi
MESSAGE="$TOTAL $PACKAGES_TXT $ACTION in $SUITE: ${PACKAGES_NAMES:0:256}$BLABLABLA"

# finally
schedule_packages $ARTIFACTS $PACKAGE_IDS
echo
echo "$MESSAGE"
if [ -z "${BUILD_URL:-}" ] && [ $TOTAL -ne 0 ] ; then
	kgb-client --conf /srv/jenkins/kgb/debian-reproducible.conf --relay-msg "$MESSAGE"
fi
echo "============================================================================="
echo "The following $TOTAL source $PACKAGES_TXT $ACTION for $SUITE: $PACKAGES_NAMES"
echo "============================================================================="
echo
