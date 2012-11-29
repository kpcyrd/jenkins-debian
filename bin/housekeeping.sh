#/bin/bash
# FIXME: make this a general and a specific housekeeping job:

# Copyright 2012 Holger Levsen <holger@layer-acht.org>
# released under the GPLv=2

#
# default settings
#
export LC_ALL=C

echo 
uptime

echo
df -h

echo
for DIR in /var/cache/apt/archives/ /var/spool/squid/ /var/cache/pbuilder/build/ /var/lib/jenkins/jobs/ ; do
	sudo du -sh $DIR 2>/dev/null
done

echo
vnstat

CHROOT_PATTERN="/chroots/chroot-tests-*"
HOUSE=$(ls $CHROOT_PATTERN)
if [ "$HOUSE" != "" ] ; then
	figlet "Warning:"
	echo
	echo "Probably manual cleanup needed:"
	echo
	echo "$ ls -la $CHROOT_PATTERN"
	echo $HOUSE
	exit 1
fi

# FIXME: no tmpfs should really mean exit 1 not 0
df |grep tmpfs > /dev/null || ( echo "Warning: no tmpfs mounts in use. Please investigate the host system." ; exit 0 )

echo
echo "No problems found, all seems good."
figlet "Ok."
