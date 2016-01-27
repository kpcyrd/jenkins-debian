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

# define work space (differently than jenkins would normally do as we run via ssh on a different node…)
WORKSPACE=$BASE/fdroid
mkdir -p $WORKSPACE

cleanup_all() {
	echo "$(date -u) - cleanup in progress..."
	killall VBoxHeadless || true
	sleep 10
	rm $WORKSPACE -r
	echo "$(date -u) - cleanup done."
}
trap cleanup_all INT TERM EXIT

# TODO:
#
#
# add locking here to only run this if no build job is running…
#
#
# not yet needed, as we don't have any build jobs yet


# make sure we have the vagrant box image cached
test -e ~/.cache/fdroidserver || mkdir -p ~/.cache/fdroidserver
cd ~/.cache/fdroidserver
wget --continue https://f-droid.org/jessie32.box || true
echo "ff6b0c0bebcb742783becbc51a9dfff5a2a0a839bfcbfd0288dcd3113f33e533  jessie32.box" > jessie32.box.sha256
sha256sum -c jessie32.box.sha256

# wipe the whole vagrant setup and start from scratch
export VAGRANT_HOME=$WORKSPACE/vagrant.d
rm -rf $VAGRANT_HOME

# FIXME: the git cloning should be part of the jenkins job…
cd $WORKSPACE
git clone https://gitlab.com/fdroid/fdroidserver.git
cd fdroidserver
echo "boot_timeout = 2400" > makebuildserver.config.py
./makebuildserver 

# we are done here, shutdown
cd buildserver
vagrant halt

# remove trap
trap - INT TERM EXIT
echo "$(date -u) - the end."
