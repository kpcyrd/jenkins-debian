#!/bin/bash

# Copyright © 2015-2016 Holger Levsen <holger@layer-acht.org>
# released under the GPLv=2

DEBUG=false
. /srv/jenkins/bin/common-functions.sh
common_init "$@"

# common code defining db access
. /srv/jenkins/bin/reproducible_common.sh

TARGET_DIR=/srv/reproducible-results/node-information/
mkdir -p $TARGET_DIR
TMPFILE_SRC=$(mktemp)
TMPFILE_NODE=$(mktemp)

echo "$(date -u) - Collecting information from nodes"
for NODE in $BUILD_NODES jenkins.debian.net ; do
	if [ "$NODE" = "jenkins.debian.net" ] ; then
		echo "$(date -u) - Trying to update $TARGET_DIR/$NODE."
		/srv/jenkins/bin/reproducible_info.sh > $TARGET_DIR/$NODE
		echo "$(date -u) - $TARGET_DIR/$NODE updated:"
		cat $TARGET_DIR/$NODE
		continue
	fi
	# call jenkins_master_wrapper.sh so we only need to track different ssh ports in one place
	# jenkins_master_wrapper.sh needs NODE_NAME and JOB_NAME
	export NODE_NAME=$NODE
	export JOB_NAME=$JOB_NAME
	echo "$(date -u) - Trying to update $TARGET_DIR/$NODE."
	/srv/jenkins/bin/jenkins_master_wrapper.sh /srv/jenkins/bin/reproducible_info.sh > $TMPFILE_SRC
	for KEY in $BUILD_ENV_VARS ; do
		VALUE=$(egrep "^$KEY=" $TMPFILE_SRC | cut -d "=" -f2-)
		if [ ! -z "$VALUE" ] ; then
			echo "$KEY=$VALUE" >> $TMPFILE_NODE
		fi
	done
	if [ -s $TMPFILE_NODE ] ; then
		mv $TMPFILE_NODE $TARGET_DIR/$NODE
		echo "$(date -u) - $TARGET_DIR/$NODE updated:"
		cat $TARGET_DIR/$NODE
	fi
	rm -f $TMPFILE_SRC $TMPFILE_NODE
done
echo

echo "$(date -u) - Showing node performance:"
TMPFILE1=$(mktemp)
TMPFILE2=$(mktemp)
TMPFILE3=$(mktemp)
NOW=$(date -u '+%Y-%m-%d %H:%m')
for i in $BUILD_NODES ; do
	sqlite3 -init $INIT ${PACKAGES_DB} \
		"SELECT build_date FROM stats_build AS r WHERE ( r.node1=\"$i\" OR r.node2=\"$i\" )" > $TMPFILE1 2>/dev/null
	j=$(wc -l $TMPFILE1|cut -d " " -f1)
	k=$(cat $TMPFILE1|cut -d " " -f1|sort -u|wc -l)
	l=$(echo "scale=1 ; ($j/$k)" | bc)
	echo "$l builds/day ($j/$k) on $i" >> $TMPFILE2
	m=$(sqlite3 -init $INIT ${PACKAGES_DB} "SELECT count(build_date) FROM stats_build AS r WHERE ( r.node1=\"$i\" OR r.node2=\"$i\" ) AND r.build_date > datetime('$NOW', '-24 hours') " 2>/dev/null)
	echo "$m builds in the last 24h on $i" >> $TMPFILE3 
done
rm $TMPFILE1 >/dev/null
sort -g -r $TMPFILE2
echo
sort -g -r $TMPFILE3
rm $TMPFILE2 $TMPFILE3 >/dev/null
echo

