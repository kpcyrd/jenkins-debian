#!/bin/bash

# Copyright 2014 Holger Levsen <holger@layer-acht.org>
#         © 2015 Mattia Rizzolo <mattia@mapreri.org>
# released under the GPLv=2

set -e

if [ ! -z "$SUDO_USER" ] ; then
	REQUESTER="$SUDO_USER"
else
	echo "Looks like you logged into this host as the jenkins user without sudoing to it. How can that be possible?!?!"
	echo "You're doing something too weird to be supported, please be normal, exiting."
	exit 1
fi

LC_USER="$REQUESTER" \
LOCAL_CALL="true" \
/srv/jenkins/bin/reproducible_remote_scheduler.py "$@"
