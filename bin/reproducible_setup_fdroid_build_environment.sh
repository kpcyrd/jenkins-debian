#!/bin/bash

# Copyright 2015-2016 Holger Levsen <holger@layer-acht.org>
# released under the GPLv=2

#
#

DEBUG=true
. /srv/jenkins/bin/common-functions.sh
common_init "$@"

# common code
. /srv/jenkins/bin/reproducible_common.sh

# define and clean work space (differently than jenkins would normally do as we run via ssh on a different node…)
WORKSPACE=$BASE/fdroid
# FIXME: add locking here to only run this if no build job is running… not yet needed, as we don't have any build jobs yet
rm $WORKSPACE -rf
mkdir -p $WORKSPACE

cleanup_all() {
	echo "$(date -u) - cleanup in progress..."
	killall VBoxHeadless || true
	sleep 10
	echo "$(date -u) - cleanup done."
}
trap cleanup_all INT TERM EXIT

# the way we handle jenkins slaves doesn't copy the workspace to the slaves
# so we need to "manually" clone the git repo here…
cd $WORKSPACE
git clone https://gitlab.com/fdroid/fdroidserver.git
cd fdroidserver

# this script is maintained upstream and is also run on Guardian
# Project's jenkins box
./jenkins-build-makebuildserver

# remove trap
trap - INT TERM EXIT
echo "$(date -u) - the end."
