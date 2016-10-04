#!/bin/bash

# Copyright 2015-2016 Holger Levsen <holger@layer-acht.org>
#                2016 Phil Hands <phil@hands.com>
# released under the GPLv=2
# based on an idea by Peter Palfrader (see bin/jenkins_node_wrapper.sh)

set -u
set -e

# don't try to run on test system
if [ "$HOSTNAME" = "jenkins-test-vm" ] ; then
	case $JOB_NAME in
		lvc_*)
			exec /srv/jenkins/bin/lvc.sh "$@"
		    echo "$(date -u) - running on $HOSTNAME, This should not happen."
		    exit 1
			;;
	esac
	echo "$(date -u) - running on $HOSTNAME, exiting successfully and cleanly immediatly."
	exit 0
fi

# define Debian build nodes in use
. /srv/jenkins/bin/jenkins_node_definitions.sh
PORT=0
get_node_ssh_port $NODE_NAME

# don't try to fetch artifacts by default
RETRIEVE_ARTIFACTS=no

# add some more params if needed,
# by default we just use the job name as param
case $JOB_NAME in
	rebootstrap_*) 	PARAMS="$JOB_NAME $@"
			;;
	lvc_*) 		PARAMS="$JOB_NAME $EXECUTOR_NUMBER TRIGGERING_BRANCH=${TRIGGERING_BRANCH:-} $@"
			RETRIEVE_ARTIFACTS=yes
			export
			;;
	*)		PARAMS="$JOB_NAME"
			;;
esac

# pseudo job used to cleanup nodes
if [ "$JOB_NAME" = "cleanup_nodes" ] ; then
	   PARAMS="$PARAMS $@"
fi

#
# main
#
set +e
ssh -o "BatchMode = yes" -p $PORT $NODE_NAME /bin/true
RESULT=$?
# abort job if host is down
if [ $RESULT -ne 0 ] ; then
	echo "$(date -u) - $NODE_NAME seems to be down, sleeping 15min before aborting this job."
	sleep 15m
	exec /srv/jenkins/bin/abort.sh
fi
set -e
# run things on the target node
RETVAL=0
ssh -o "BatchMode = yes" -p $PORT $NODE_NAME "$PARAMS" || {
	# mention failures, but continue since we might want the artifacts anyway
	RETVAL=$?
	printf "\nSSH EXIT CODE: %s\n" $RETVAL
}

# grab artifacts and tidy up at the other end
if [ "$RETRIEVE_ARTIFACTS" = "yes" ] ; then
	RESULTS="$WORKSPACE/workspace/$JOB_NAME/results"
	NODE_RESULTS="/var/lib/jenkins/jobs/$JOB_NAME/workspace/results"
	echo "$(date -u) - retrieving artifacts."
	set -x
	mkdir -p "$RESULTS"
	rsync -r --delete -v -e "ssh -o 'Batchmode = yes' -p $PORT" "$NODE_NAME:$NODE_RESULTS/" "$RESULTS/"
	ssh -o "BatchMode = yes" -p $PORT $NODE_NAME "rm -r $NODE_RESULTS"
	ls -lad "$RESULTS"
	ls -la "$RESULTS"
	echo "WORKSPACE=$WORKSPACE"
fi

exit $RETVAL
