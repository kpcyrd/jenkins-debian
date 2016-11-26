#!/bin/sh

for f in /target/etc/plymouth/plymouthd.conf /target/opt/ltsp/i386/etc/plymouth/plymouthd.conf ; do
	# this is a joyous race condition
	while [ ! -e $f ] ; do
		sleep 1
	done

	rm -f $f
done
