#!/bin/bash

# Copyright 2012-2014 Holger Levsen <holger@layer-acht.org>
# released under the GPLv=2

DEBUG=false
. /srv/jenkins/bin/common-functions.sh
common_init "$@"

# let's have readable output here
set +x

check_for_mounted_chroots() {
	CHROOT_PATTERN="/chroots/${1}-*"
	OUTPUT=$(mktemp)
	ls $CHROOT_PATTERN 2>/dev/null > $OUTPUT || true
	if [ -s $OUTPUT ] ; then
		figlet "Warning:"
		echo
		echo "Probably manual cleanup needed:"
		echo
		echo "$ ls -la $CHROOT_PATTERN"
		# List the processes using the partition
		echo
		fuser -mv $CHROOT_PATTERN
		cat $OUTPUT
		rm $OUTPUT
		exit 1
	fi
	rm $OUTPUT
}

chroot_checks() {
	check_for_mounted_chroots $1
	report_disk_usage /chroots
	report_disk_usage /schroots
	echo "WARNING: should remove directories in /(s)chroots which are older than a month."
}

report_disk_usage() {
	du -schx /var/lib/jenkins/jobs/${1}* |grep total |sed -s "s#total#${1} jobs#"
}

report_filetype_usage() {
	OUTPUT=$(mktemp)
	echo "File system use in $1 for $2 files:"
	echo
	find /var/lib/jenkins/jobs/${1}* -type f -name "*.${2}" 2>/dev/null|xargs -r du -sch |grep total |sed -s "s#total#$1 .$2 files#" > $OUTPUT
	if [ "$3" = "warn" ] && [ -s $OUTPUT ] ; then
		echo "Warning: there are $2 files and there should not be any."
		cat $OUTPUT
		echo
		echo "Checking for running QEMU processes: (might be causing these files to be there right now)"
		ps fax | grep [q]emu-system | grep -v grep || true
	else
		cat $OUTPUT
	fi
	rm $OUTPUT
}

report_squid_usage() {
	REPORT=/var/www/calamaris/calamaris.txt
	if [ -z $1 ] ; then
		cat $REPORT
	else
		head -31 $REPORT
	fi
}

wait4idle() {
	echo "Waiting until no $1.sh process runs.... $(date)"
	while [ $(ps fax | grep -c $1.sh) -gt 1 ] ; do
		sleep 30
	done
	echo "Done waiting: $(date)"
}

general_housekeeping() {
	echo
	uptime

	echo
	# ignore unreadable /media fuse mountpoints from guestmount
	df -h 2>/dev/null || true

	echo
	for DIR in /var/cache/apt/archives/ /var/spool/squid/ /var/cache/pbuilder/build/ /var/lib/jenkins/jobs/ /chroots /schroots ; do
		sudo du -shx $DIR 2>/dev/null
	done
	JOB_PREFIXES=$(ls -1 /var/lib/jenkins/jobs/|cut -d "_" -f1|sort -f -u)
	for PREFIX in $JOB_PREFIXES ; do
		report_disk_usage $PREFIX
	done

	echo
	vnstat

	(df 2>/dev/null || true ) | grep tmpfs > /dev/null || ( echo ; echo "Warning: no tmpfs mounts in use. Please investigate the host system." ; exit 1 )
}

#
# if $1 is empty, we do general housekeeping, else for some subgroup of all jobs
#
if [ -z $1 ] ; then
	general_housekeeping
	report_squid_usage brief
else
	case $1 in
		chroot-installation*)		wait4idle $1
						report_disk_usage $1
						chroot_checks $1
						;;
		g-i-installation)		wait4idle $1
						report_disk_usage $1
						report_filetype_usage $1 raw warn
						report_filetype_usage $1 iso
						report_filetype_usage $1 png
						report_filetype_usage $1 ppm warn
						report_filetype_usage $1 bak warn
						echo "WARNING: there is no check / handling on stale lvm volumes"
						;;
		squid)				report_squid_usage
						;;
		*)				;;
	esac
fi

echo
echo "No (big) problems found, all seems good."
figlet "Ok."
