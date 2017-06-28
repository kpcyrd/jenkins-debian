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
# is the filesystem writetable?
#
echo "$(date -u) - testing whether /tmp is writable..."
TEST=$(mktemp --tmpdir=/tmp rwtest-XXXXXX)
if [ -z "$TEST" ] ; then
	echo "Failure to write a file in /tmp, assuming read-only filesystem."
	exit 1
fi
rm $TEST > /dev/null

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
# check for hanging mounts
#
echo "$(date -u) - testing whether running 'mount' takes forever..."
timeout -s 9 15 mount > /dev/null
TIMEOUT=$?
if [ $TIMEOUT -ne 0 ] ; then
	echo "$(date -u) - running 'mount' takes forever, giving up."
	exit 1
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
# check for cleaned up kernels
# (on Ubuntu systems only, as those have free spaces issues on /boot frequently)
#
if [ "$(lsb_release -si)" = "Ubuntu" ] ; then
	echo "$(date -u) - testing whether only one kernel is installed..."
	if [ "$(ls /boot/vmlinuz-*|wc -l)" != "1" ] ; then
		echo "Warning, more than one kernel in /boot:"
		ls -lart /boot/vmlinuz-*
		df -h /boot
		DIRTY=true
	fi
fi

#
# check for haveged running
#
echo "$(date -u) - testing 'haveged' is running..."
HAVEGED="$(ps fax | grep '/usr/sbin/haveged' | grep -v grep || true)"
if [ -z "$HAVEGED" ] ; then
	echo "$(date -u) - haveged ain't running, giving up."
	systemctl status haveged
	exit 1
fi

#
# checks only for the main node
#
if [ "$HOSTNAME" = "$MAINNODE" ] ; then
	#
	# sometimes deleted jobs come back as zombies
	# and we dont know why and when that happens,
	# so just report those zombies here.
	#
	ZOMBIES=$(ls -1d /var/lib/jenkins/jobs/ | egrep '(reproducible_builder_amd64|reproducible_builder_i386|reproducible_builder_armhf|reproducible_builder_arm64|chroot-installation_wheezy)')
	if [ ! -z "$ZOMBIES" ] ; then
		echo "Warning, rise of the jenkins job zombies has started again, these jobs should not exist:"
		echo -e "$ZOMBIES"
		DIRTY=TRUE
		echo
	fi
fi


#
# finally
#
if ! $DIRTY ; then
	echo "$(date -u ) - Everything seems to be fine."
	echo
fi

echo "$(date -u) - the end."


