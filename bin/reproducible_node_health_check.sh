#!/bin/bash

# Copyright 2014-2017 Holger Levsen <holger@layer-acht.org>
#         © 2015 Mattia Rizzolo <mattia@mapreri.org>
# released under the GPLv=2

DEBUG=false
. /srv/jenkins/bin/common-functions.sh
common_init "$@"

# common code defining db access
. /srv/jenkins/bin/reproducible_common.sh

# some defaults
DIRTY=false
REP_RESULTS=/srv/reproducible-results

show_fstab_and_mounts() {
	echo "################################"
	echo "/dev/shm and /run/shm on $HOSTNAME"
	echo "################################"
	ls -lartd /run/shm /dev/shm/
	echo "################################"
	echo "/etc/fstab on $HOSTNAME"
	echo "################################"
	cat /etc/fstab
	echo "################################"
	echo "mount output on $HOSTNAME"
	echo "################################"
	mount
	echo "################################"
	DIRTY=true
}

#
# we fail hard
#
set -e

#
# check for /dev/shm being mounted properly
#
echo "$(date -u) - testing whether /dev/shm is mounted correctly..."
mount | egrep -q "^tmpfs on /dev/shm"
if [ $? -ne 0 ] ; then
	echo "Warning: /dev/shm is not mounted correctly on $HOSTNAME, it should be a tmpfs, please tell the jenkins admins to fix this."
	show_fstab_and_mounts
fi
test "$(stat -c %a -L /dev/shm)" = 1777
if [ $? -ne 0 ] ; then
	echo "Warning: /dev/shm is not mounted correctly on $HOSTNAME, it should be mounted with 1777 permissions, please tell the jenkins admins to fix this."
	show_fstab_and_mounts
fi
#
# check for /run/shm being a link to /dev/shm
#
echo "$(date -u) - testing whether /run/shm is a link..."
if ! test -L /run/shm ; then
	echo "Warning: /run/shm is not a link on $HOSTNAME, please tell the jenkins admins to fix this."
	show_fstab_and_mounts
elif [ "$(readlink /run/shm)" != "/dev/shm" ] ; then
	echo "Warning: /run/shm is a link, but not pointing to /dev/shm on $HOSTNAME, please tell the jenkins admins to fix this."
	show_fstab_and_mounts
fi

#
# check for correct MTU
#
echo "$(date -u) - testing whether the network interfaces MTU is 1500..."
if [ "$(ip link | sed -n '/LOOPBACK\|NOARP/!s/.* mtu \([0-9]*\) .*/\1/p' | sort -u)" != "1500" ] ; then
	ip link
	echo "$(date -u) - network interfaces MTU != 1500 - this is wrong.  => please \`sudo ifconfig eth0 mtu 1500\`"
	# should probably turn this into a warning if this becomes to annoying
	irc_message debian-reproducible "$HOSTNAME has wrong MTU, please tell the jenkins admins to fix this.  (sudo ifconfig eth0 mtu 1500)"
	exit 1
fi

#
# check for correct future
#
# (yes this is hardcoded but meh…)
echo "$(date -u) - testing whether the time is right..."
if [ "$(date +%Y)" = "2019" ] ; then
	echo "Warning, today is the wrong future: $(date -u)."
	DIRTY=true
elif [ "$(date +%Y)" = "2018" ] ; then
	echo "Good, today is the right future: $(date -u)."
else
	echo "Cherrish today, $(date -u)."
fi

#
# finally
#
if ! $DIRTY ; then
	echo "$(date -u ) - Everything seems to be fine."
	echo
fi

echo "$(date -u) - the end."


