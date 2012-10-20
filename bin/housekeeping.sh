#/bin/bash

# Copyright 2012 Holger Levsen <holger@layer-acht.org>
# released under the GPLv=2

echo 
uptime
echo
df -h
echo

HOUSE=$(ls /chroots/)
if [ "$HOUSE" != "" ] ; then
	figlet "Warning:"
	echo
	echo "Probably manual cleanup needed:"
	echo
	echo "$ ls -la /chroots/"
	ls -la /chroots/
	exit 1
fi

echo "No problems found, all seems good."
figlet "Ok."
