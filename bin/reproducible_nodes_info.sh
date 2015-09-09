#!/bin/bash

# Copyright © 2015 Holger Levsen <holger@layer-acht.org>
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

for NODE in bpi0-armhf-rb.debian.net hb0-armhf-rb.debian.net wbq0-armhf-rb.debian.net cbxi4pro0-armhf-rb.debian.net profitbricks-build1-amd64.debian.net profitbricks-build2-amd64.debian.net ; do
	# call jenkins_master_wrapper.sh so we only need to track different ssh ports in one place
	# jenkins_master_wrapper.sh needs NODE_NAME and JOB_NAME
	export NODE_NAME=$NODE
	export JOB_NAME=reproducible_nodes_info
	/srv/jenkins/bin/jenkins_master_wrapper.sh /srv/jenkins/bin/reproducible_info.sh > $TMPFILE_SRC
	for KEY in ARCH NUM_CPU CPU_MODEL DATETIME ; do
		VALUE=$(egrep "^$KEY=" $TMPFILE_SRC | cut -d "=" -f2-)
		if [ ! -z "$VALUE" ] ; then
			echo "$KEY=$VALUE" >> $TMPFILE_NODE
		fi
	done
	if [ -s $TMPFILE_NODE ] ; then
		mv $TMPFILE_NODE $TARGET_DIR/$NODE
	fi
	rm -f $TMPFILE_SRC $TMPFILE_NODE
done

