#!/bin/bash

# Copyright 2014 Holger Levsen <holger@layer-acht.org>
#         © 2015 Mattia Rizzolo <mattia@mapreri.org>
# released under the GPLv=2

DEBUG=false
. /srv/jenkins/bin/common-functions.sh
common_init "$@"

# common code defining db access
. /srv/jenkins/bin/reproducible_common.sh

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

if [ ! -z "$SUDO_USER" ] ; then
	REQUESTER="$SUDO_USER"
else
	echo "Looks like you logged into this host as the jenkins user without sudoing to it. How can that be possible?!?!"
	REQUESTER="$USER"
fi

CANDIDATES="$@"
if [ ${#} -gt 50 ] && [ "$NOTIFY" = "true" ] ; then
	echo
	figlet "No."
	echo "Do not schedule more than 50 packages with notification. If you really really need to spam the IRC channel this much, use a loop to achieve that. Exiting."
	echo
	exit 1
fi

# finally
schedule_packages $CANDIDATES
