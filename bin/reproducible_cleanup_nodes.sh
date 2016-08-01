#!/bin/bash

# Copyright © 2015-2016 Holger Levsen <holger@layer-acht.org>
# released under the GPLv=2

DEBUG=false
. /srv/jenkins/bin/common-functions.sh
common_init "$@"

# common code defining db access
. /srv/jenkins/bin/reproducible_common.sh

# only run this on the main node as jenkins
if [ "$HOSTNAME" != "jenkins" ] ; then
	echo "this script must only be run on the main node, aborting."
	exit 1
elif [ "$(whoami)" != "jenkins" ] ; then
	echo "this script must only be run as jenkins user, aborting."
	exit 1
fi

# deny running this if jenkins is still running
if [ "$1" != "--force" ] ; then
	RESULT=$(ps fax|grep '/usr/share/jenkins/jenkins.war'|grep -v grep||true)
	if [ -n "$RESULT" ] ; then
		echo "jenkins is still running, aborting."
		exit 1
	else
		echo "jenkins is not running, ok, let's go."
	fi
fi

# simple confirmation needed
echo
echo "Warning: running this will kill all processes by the 1111, 2222 and jenkins"
echo "         users. Press return if you want this, else better press CTRL-C now."
echo
read

export JOB_NAME="cleanup_nodes"
for NODE in $BUILD_NODES ; do
	# call jenkins_master_wrapper.sh so we only need to track different ssh ports in one place
	# jenkins_master_wrapper.sh needs NODE_NAME and JOB_NAME
	export NODE_NAME=$NODE
	echo "$(date -u) - Killing build processes on $NODE in background now."
	/srv/jenkins/bin/jenkins_master_wrapper.sh /srv/jenkins/bin/reproducible_slay.sh &
done

sleep 15
echo "killing all ssh and sleep processes now. (press enter || ctrl-c)"
read
set +e
killall ssh
killall sleep
killall -9 ssh
killall -9 sleep
echo "$(date -u) - slaughtering done. Happy rebooting or whatever you plan to do."

