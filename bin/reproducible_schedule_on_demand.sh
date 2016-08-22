#!/bin/bash

# Copyright 2014,2016 Holger Levsen <holger@layer-acht.org>
#         © 2015 Mattia Rizzolo <mattia@mapreri.org>
# released under the GPLv=2

set -e

if [ ! -z "$SUDO_USER" ] ; then
	REQUESTER="$SUDO_USER"
else
	echo "Please run this script as the jenkins user, exiting."
	exit 1
fi

LC_USER="$REQUESTER" \
LOCAL_CALL="true" \
/srv/jenkins/bin/reproducible_remote_scheduler.py "$@"
