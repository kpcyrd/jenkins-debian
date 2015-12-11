#!/bin/bash

# Copyright 2015 Holger Levsen <holger@layer-acht.org>
# released under the GPLv=2

#
# configures mock for a given distro and architecture
#

DEBUG=false
. /srv/jenkins/bin/common-functions.sh
common_init "$@"

if [ -z "$1" ] || [ -z "$2" ] ; then
	echo "Need distro and architecture as params"
	exit 1
fi
DISTRO=$1
ARCHITECTURE=$2

echo "$(date -u) - showing setup."
dpkg -l mock
id
echo "$(date -u) - starting to cleanly configure mock for ${DISTRO} on ${ARCHITECTURE}."
mock -r ${DISTRO}-${ARCHITECTURE} --clean
mock -r ${DISTRO}-${ARCHITECTURE} --init
echo "$(date -u) - mock configured for ${DISTRO} on ${ARCHITECTURE}."
