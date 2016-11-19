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

export LC_USER="$REQUESTER"
export LOCAL_CALL="true"
if [ -z "$1" ] ; then
        /srv/jenkins/bin/reproducible_remote_scheduler.py --help
else
        /srv/jenkins/bin/reproducible_remote_scheduler.py "$@"
fi
