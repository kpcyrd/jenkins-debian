#!/bin/bash

set -u
set -e

# don't try to run on test system
if [ "$HOSTNAME" = "jenkins-test-vm" ] ; then
	echo "$(date -u) - running on $HOSTNAME, exiting successfully and cleanly immediatly."
	exit 0
fi

# define Debian build nodes in use
. /srv/jenkins/bin/jenkins_node_definitions.sh
PORT=0
get_node_ssh_port $NODE_NAME

# by default we just use the job name as param
PARAMS="$JOB_NAME"

# though this could be used for other jobs as well...
if [[ "$JOB_NAME" =~ rebootstrap_.* ]] ; then
   PARAMS="$PARAMS $@"
fi

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
# finally
exec ssh -o "BatchMode = yes" -p $PORT $NODE_NAME "$PARAMS"

