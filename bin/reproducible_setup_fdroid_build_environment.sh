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
cd $WORKSPACE

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
git clone https://gitlab.com/fdroid/fdroidserver.git
cd fdroidserver
./makebuildserver 
