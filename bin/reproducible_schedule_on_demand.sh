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
CANDIDATES="$@"
check_candidates
if [ ${#PACKAGE_IDS} -gt 256 ] ; then
	BLABLABLA="..."
fi
ACTION="manually rescheduled"
if [ -n "${BUILD_URL:-}" ] ; then
	ACTION="rescheduled by $BUILD_URL"
fi
MESSAGE="$TOTAL $PACKAGES_TXT $ACTION for $SUITE: ${PACKAGES_NAMES:0:256}$BLABLABLA"

# finally
schedule_packages $PACKAGE_IDS
echo
echo "$MESSAGE"
if [ -z "${BUILD_URL:-}" ] ; then
	kgb-client --conf /srv/jenkins/kgb/debian-reproducible.conf --relay-msg "$MESSAGE"
fi
echo "============================================================================="
echo "The following $TOTAL source $PACKAGES_TXT $ACTION for $SUITE: $PACKAGES_NAMES"
echo "============================================================================="
echo
