#/bin/bash

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
