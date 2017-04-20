#!/bin/bash

# Copyright © 2015-2016 Holger Levsen <holger@layer-acht.org>
# Copyright © 2016-2017 Hans-Christoph Steiner (hans@guardianproject.info)
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
ls -lR ~/.vagrant.d/ || echo no access
virsh --connect qemu:///system list --all || echo cannot virsh list
cat /etc/issue

# delete old libvirt instances, until the fdroid tools do it reliably
virsh --connect qemu:///system undefine builder_default || echo nothing to undefine
virsh --connect qemu:///system vol-delete --pool default /var/lib/libvirt/images/builder_default.img || echo nothing to delete

# the way we handle jenkins slaves doesn't copy the workspace to the slaves
# so we need to "manually" clone the git repo here…
cd $WORKSPACE
#git clone https://gitlab.com/fdroid/fdroidserver.git
git clone https://gitlab.com/uniqx/fdroidserver.git
cd fdroidserver
git checkout jenkins.debian.net # normally master too

# set up Android SDK to use the Debian packages in stretch
export ANDROID_HOME=/usr/lib/android-sdk

# this script is maintained upstream and is also run on Guardian
# Project's jenkins box
./jenkins-build-makebuildserver

# remove trap
trap - INT TERM EXIT
echo "$(date -u) - the end."
