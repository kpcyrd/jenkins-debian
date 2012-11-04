#/bin/bash

# Copyright 2012 Holger Levsen <holger@layer-acht.org>
# released under the GPLv=2

echo 
uptime
echo
df -h
echo
for DIR in /var/cache/apt/archives/ /var/spool/squid/ /var/lib/jenkins/jobs/ ; do
	sudo du -sh $DIR
done
echo
vnstat
echo

CHROOT_PATTERN="/chroots/chroot-tests-*"
HOUSE=$(ls $CHROOT_PATTERN)
if [ "$HOUSE" != "" ] ; then
	figlet "Warning:"
	echo
	echo "Probably manual cleanup needed:"
	echo
	echo "$ ls -la /chroots/"
	echo $HOUSE
	exit 1
fi

echo "No problems found, all seems good."
figlet "Ok."
