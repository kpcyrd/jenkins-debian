#!/bin/bash

# Copyright © 2015-2017 Holger Levsen (holger@layer-acht.org)
# Copyright © 2017 Hans-Christoph Steiner (hans@guardianproject.info)
# released under the GPLv=2

#
#

DEBUG=true
. /srv/jenkins/bin/common-functions.sh
common_init "$@"

# common code
. /srv/jenkins/bin/reproducible_common.sh

GIT_REPO=https://gitlab.com/fdroid/fdroidserver

# define and clean work space on the machine actually running the
# build. jenkins.debian.net does not use Jenkins slaves.  Instead
# /srv/jenkins/bin/jenkins_master_wrapper.sh runs this script on the
# slave using a directly call to ssh, so this script has to do all
# of the workspace setup.
export WORKSPACE=$BASE/reproducible_fdroid_build_apps
if [ -e $WORKSPACE/.git ]; then
    # reuse the git repo if possible, to keep all the setup in fdroiddata/
    cd $WORKSPACE
    git remote set-url origin $GIT_REPO
    git fetch --tags
    git clean -fdx
    git reset --hard
    git checkout master
    git reset --hard origin/master
    git clean -fdx
else
    rm -rf $WORKSPACE
    git clone $GIT_REPO $WORKSPACE
    cd $WORKSPACE
fi

cleanup_all() {
	echo "$(date -u) - cleanup in progress..."
	killall VBoxHeadless || true
	sleep 10
	echo "$(date -u) - cleanup done."
}
trap cleanup_all INT TERM EXIT

./jenkins-build

# remove trap
trap - INT TERM EXIT
echo "$(date -u) - the end."
