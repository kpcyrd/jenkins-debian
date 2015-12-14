#!/bin/bash

# Copyright 2015 Holger Levsen <holger@layer-acht.org>
# released under the GPLv=2

#
# configure mock for a given release and architecture
#

DEBUG=false
. /srv/jenkins/bin/common-functions.sh
common_init "$@"

if [ -z "$1" ] || [ -z "$2" ] ; then
	echo "Need release and architecture as params."
	exit 1
fi
RELEASE=$1
ARCH=$2
# not used yet:
UNIQEEXT="mock_${JOB_NAME#reproducible_builder_${RELEASE}_$ARCH}}"

echo "$(date -u) - showing setup."
dpkg -l mock
id
echo "$(date -u) - cleaning yum."
rm ~/.rpmdb -rf
yum -v clean all
yum -v check
yum -v repolist all
echo "$(date -u) - starting to cleanly configure mock for $RELEASE on $ARCH."
echo "$(date -u) - mock --clean"
mock -r $RELEASE-$ARCH --resultdir=. -v --clean
echo "$(date -u) - mock --scrub=all"
mock -r $RELEASE-$ARCH --resultdir=. -v --scrub=all
tree /var/cache/mock/
echo "$(date -u) - mock --init"
mock -r $RELEASE-$ARCH --resultdir=. -v --init
echo "$(date -u) - mock configured for $RELEASE on $ARCH."
echo "$(date -u) - mock --install rpm-build"
mock -r $RELEASE-$ARCH --resultdir=. -v --install rpm-build yum
echo "$(date -u) - mock --update"
mock -r $RELEASE-$ARCH --resultdir=. -v --update
# AIUI, this should work but fails with "UnboundLocalError: local variable 'chrootstate' referenced before assignment"
# as can be seen in https://jenkins.debian.net/view/reproducible/job/reproducible_setup_mock_fedora-23_x86_64_profitbricks3/13/console
#echo "$(date -u) - yum makecache"
#mock -r $RELEASE-$ARCH --resultdir=. -v --chroot yum makecache

