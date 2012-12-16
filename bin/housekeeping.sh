#/bin/bash

# Copyright 2012 Holger Levsen <holger@layer-acht.org>
# released under the GPLv=2

#
# default settings
#
export LC_ALL=C
set -e

check_for_mounted_chroots() {
	CHROOT_PATTERN="/chroots/$1-*"
	OUTPUT=$(ls $CHROOT_PATTERN 2>/dev/null)
	if [ "$OUTPUT" != "" ] ; then
		figlet "Warning:"
		echo
		echo "Probably manual cleanup needed:"
		echo
		echo "$ ls -la $CHROOT_PATTERN"
		# List the processes using the partition
		echo
		fuser -mv $CHROOT_TARGET
		echo $OUTPUT
		exit 1
	fi
}

report_disk_usage() {
	du -schx /var/lib/jenkins/jobs/$1_* |grep total |sed -s "s#total#$1 jobs#"
	# FIXME: if $2 is given check, that disk usage is below $2 GB
}

report_squid_usage() {
	cat /var/www/calamaris/calamaris.txt
}

general_housekeeping() {
	echo
	uptime

	echo
	df -h

	echo
	for DIR in /var/cache/apt/archives/ /var/spool/squid/ /var/cache/pbuilder/build/ /var/lib/jenkins/jobs/ ; do
		sudo du -shx $DIR 2>/dev/null
	done
	JOB_PREFIXES=$(ls -1 /var/lib/jenkins/jobs/|cut -d "_" -f1|sort -f -u)
	for PREFIX in $JOB_PREFIXES ; do
		report_disk_usage $PREFIX
	done

	echo
	vnstat

	df |grep tmpfs > /dev/null || ( echo ; echo "Warning: no tmpfs mounts in use. Please investigate the host system." ; exit 1 )
}

#
# if $1 is set, we do housekeeping for a group of jobs, else general
#
if [ -n $1 ] ; then
	report_disk_usage $1
	if [ "$1" = "chroot-installation" ] ; then
		check_for_mounted_chroots $1
	fi
else
	general_housekeeping
	report_squid_usage
fi

echo
echo "No problems found, all seems good."
figlet "Ok."
