#!/bin/bash

# Copyright 2015 Holger Levsen <holger@layer-acht.org>
# released under the GPLv=2

DEBUG=false
. /srv/jenkins/bin/common-functions.sh
common_init "$@"

set -e

cleanup_all() {
	cd
	rm $TMPDIR -r
	echo "$(date -u) - $TMPDIR deleted."
	if [ "$MODE" != "master" ] ;
		schroot --end-session -c arch-$SRCPACKAGE
	fi
}

handle_remote_error() {
	MESSAGE="${BUILD_URL}console got remote error $1"
	echo "$(date -u ) - $MESSAGE" | tee -a /var/log/jenkins/reproducible-remote-error.log
	echo "Sleeping 5m before aborting the job."
	sleep 5m
	exec /srv/jenkins/bin/abort.sh
	exit 0
}

first_build() {
	echo "============================================================================="
	echo "Building ${SRCPACKAGE} for Archlinux on $(hostname -f) now."
	echo "Date:     $(date)"
	echo "Date UTC: $(date -u)"
	echo "============================================================================="
	set -x
	schroot --begin-session --session-name=arch-$SRCPACKAGE -c jenkins-reproducible-arch
	schroot --run-session -c arch-$SRCPACKAGE --directory /tmp -- cp -r /var/abs/core/$SRCPACKAGE /tmp
	schroot --run-session -c arch-$SRCPACKAGE --directory /tmp/$SRCPACKAGE -- makepkg --skippgpcheck
	schroot --end-session -c arch-$SRCPACKAGE
	if ! "$DEBUG" ; then set +x ; fi
}

second_build() {
	echo "============================================================================="
	echo "Re-Building ${SRCPACKAGE} for Archlinux on $(hostname -f) now."
	echo "Date:     $(date)"
	echo "Date UTC: $(date -u)"
	echo "============================================================================="
	set -x
	schroot --begin-session --session-name=arch-$SRCPACKAGE -c jenkins-reproducible-arch
	schroot --run-session -c arch-$SRCPACKAGE --directory /tmp -- cp -r /var/abs/core/$SRCPACKAGE /tmp
	schroot --run-session -c arch-$SRCPACKAGE --directory /tmp/$SRCPACKAGE -- makepkg --skippgpcheck
	schroot --end-session -c arch-$SRCPACKAGE
	if ! "$DEBUG" ; then set +x ; fi
}

remote_build() {
	local BUILDNR=$1
	local NODE=profitbricks-build3-amd64.debian.net
	local PORT=22
	set +e
	ssh -p $PORT $NODE /bin/true
	RESULT=$?
	# abort job if host is down
	if [ $RESULT -ne 0 ] ; then
		SLEEPTIME=$(echo "$BUILDNR*$BUILDNR*5"|bc)
		echo "$(date -u) - $NODE seems to be down, sleeping ${SLEEPTIME}min before aborting this job."
		sleep ${SLEEPTIME}m
		exec /srv/jenkins/bin/abort.sh
	fi
	ssh -p $PORT $NODE /srv/jenkins/bin/reproducible_build_arch_pkg.sh $BUILDNR ${SRCPACKAGE} ${TMPDIR}
	RESULT=$?
	if [ $RESULT -ne 0 ] ; then
		handle_remote_error "with exit code $RESULT from $NODE for build #$BUILDNR for ${SRCPACKAGE}"
	fi
	rsync -e "ssh -p $PORT" -r $NODE:$TMPDIR/b$BUILDNR $TMPDIR/
	RESULT=$?
	if [ $RESULT -ne 0 ] ; then
		echo "$(date -u ) - rsync from $NODE failed, sleeping 2m before re-trying..."
		sleep 2m
		rsync -e "ssh -p $PORT" -r $NODE:$TMPDIR/b$BUILDNR $TMPDIR/
		RESULT=$?
		if [ $RESULT -ne 0 ] ; then
			handle_remote_error "when rsyncing remote build #$BUILDNR results from $NODE"
		fi
	fi
	ls -R $TMPDIR
	ssh -p $PORT $NODE "rm -r $TMPDIR"
	set -e
}

build_rebuild() {
	mkdir b1 b2
	remote_build 1
	remote_build 2
}

#
# below is what controls the world
#

TMPDIR=$(mktemp --tmpdir=/srv/reproducible-results -d)  # where everything actually happens
trap cleanup_all INT TERM EXIT
cd $TMPDIR

DATE=$(date -u +'%Y-%m-%d %H:%M')
START=$(date +'%s')
RBUILDLOG=$(mktemp --tmpdir=$TMPDIR)
BUILDER="${JOB_NAME#reproducible_builder_}/${BUILD_ID}"

#
# determine mode
#
if [ "$1" = "" ] ; then
	MODE="master"
elif [ "$1" = "1" ] || [ "$1" = "2" ] ; then
	MODE="$1"
	SRCPACKAGE="$2"
	TMPDIR="$3"
	[ -d $TMPDIR ] || mkdir -p $TMPDIR
	cd $TMPDIR
	mkdir b$MODE
	if [ "$MODE" = "1" ] ; then
		first_build
	else
		second_build
	fi
	mv -v /tmp/$PKG $TMPDIR/b$mode
	echo "$(date -u) - build #$MODE for $SRCPACKAGE on $HOSTNAME done."
	exit 0
fi

#
# main - only used in master-mode
#
SRCPACKAGE=sudo
build_rebuild
#call_diffoscope

cd
cleanup_all
trap - INT TERM EXIT

