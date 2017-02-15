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

# report info about virtualization
(dmesg | grep -i -e hypervisor -e qemu -e kvm) || true
(lspci | grep -i -e virtio -e virtualbox -e qemu -e kvm) || true
lsmod
if systemd-detect-virt -q ; then
        echo "Virtualization is used:" `systemd-detect-virt`
else
        echo "No virtualization is used."
fi
sudo /bin/chmod -R a+rX /var/lib/libvirt/images
ls -ld /var/lib/libvirt/images
ls -l /var/lib/libvirt/images || echo no access
ls -lR ~/.vagrant.d/
virsh --connect qemu:///system list --all
cat /etc/issue

# the way we handle jenkins slaves doesn't copy the workspace to the slaves
# so we need to "manually" clone the git repo here…
cd $WORKSPACE
#git clone https://gitlab.com/fdroid/fdroidserver.git
git clone https://gitlab.com/eighthave/fdroidserver.git
cd fdroidserver
git checkout jenkins # normally master too

# set up Android SDK to use the Debian packages in stretch
export ANDROID_HOME=/usr/lib/android-sdk

# this script is maintained upstream and is also run on Guardian
# Project's jenkins box
./jenkins-build-makebuildserver

# ignore username/password prompt for non-existant repos
git config --global url."https://fakeusername:fakepassword@github.com".insteadOf https://github.com
git config --global url."https://fakeusername:fakepassword@gitlab.com".insteadOf https://gitlab.com
git config --global url."https://fakeusername:fakepassword@bitbucket.org".insteadOf https://bitbucket.org

# now build the whole archive
cd $WORKSPACE
git clone https://gitlab.com/fdroid/fdroiddata.git
cd fdroiddata
echo "build_server_always = True" > config.py
$WORKSPACE/fdroidserver/fdroid build --verbose --latest --all

# remove trap
trap - INT TERM EXIT
echo "$(date -u) - the end."
