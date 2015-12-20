#!/bin/bash

# Copyright 2015 Holger Levsen <holger@layer-acht.org>
# released under the GPLv=2

DEBUG=false
. /srv/jenkins/bin/common-functions.sh
common_init "$@"

# common code
. /srv/jenkins/bin/reproducible_common.sh

set -e

cleanup_all() {
	cd
	# delete mock result dir
	if [ ! -z $SRCPACKAGE ] && [ -d /tmp/$SRCPACKAGE-$(basename $TMPDIR) ] ; then
		rm -r /tmp/$SRCPACKAGE-$(basename $TMPDIR)
	fi
	# delete main work dir (only on master)
	if [ "$MODE" = "master" ] ; then
		rm $TMPDIR -r
		echo "$(date -u) - $TMPDIR deleted."
	fi
	rm -f $DUMMY > /dev/null || true
}

handle_remote_error() {
	MESSAGE="${BUILD_URL}console got remote error $1"
	echo "$(date -u ) - $MESSAGE" | tee -a /var/log/jenkins/reproducible-remote-error.log
	echo "Sleeping 5m before aborting the job."
	sleep 5m
	exec /srv/jenkins/bin/abort.sh
	exit 0
}

update_mock() {
	echo "$(date -u ) - checking whether to update mock and yum for $RELEASE ($ARCH) on $HOSTNAME."
	local STAMP="${RPM_STAMPS}-$RELEASE-$ARCH"
	touch -d "$(date -u -d "6 hours ago" '+%Y-%m-%d %H:%M') UTC" $DUMMY
	if [ ! -f $STAMP ] || [ $DUMMY -nt $STAMP ] ; then
		echo "$(date -u ) - updating mock for $RELEASE ($ARCH) on $HOSTNAME now..."
		mock -r $RELEASE-$ARCH --uniqueext=$UNIQUEEXT --resultdir=. --cleanup-after -v --update 2>&1
		echo "$(date -u ) - mock updated."
		yum -v --releasever=23 check-update # FIXME: dont hard-code releasever here.
		echo "$(date -u ) - yum updated."
		touch $STAMP
	else
		echo "$(date -u ) - mock and yum not updated, last update was at $(TZ=UTC ls --full-time $STAMP | cut -d ' ' -f6-7 | cut -d '.' -f1) UTC."
	fi
	rm $DUMMY > /dev/null
}

download_package() {
	echo "$(date -u ) - downloading ${SRCPACKAGE} for $RELEASE now."
	yumdownloader --source ${SRCPACKAGE}
	SRC_RPM="$(ls *.src.rpm)"
}

choose_package() {
	local MIN_AGE=7
	touch -d "$(date -u -d "$MIN_AGE days ago" '+%Y-%m-%d %H:%M') UTC" $DUMMY
	if [ ! -f ${RPM_PKGS}_$RELEASE ] || [ $DUMMY -nt ${RPM_PKGS}_$RELEASE ] ; then
		echo "$(date -u ) - updating list of available packages for $RELEASE"
		SEARCHTERMS="apache2 awesome bash fedora firefox gcc gnome gnu gpg ipa kde linux mock openssl pgp redhat rpm ssh system-config systemd xfce xorg yum"
		echo "$(date -u ) - for now, instead of building everything, only packages matching these searchterms are build: $SEARCHTERMS"
		local i=""
		# http://fedoraproject.org/wiki/Packaging:NamingGuidelines describes the rpm naming scheme
		# the awk command removes the last two "columns" seperated by "-"
		# so system-config-printer-1.5.7-5.fc23.src.rpm becomes system-config-printer
		( for i in $SEARCHTERMS ; do repoquery --qf "%{sourcerpm}" "*$i*" | awk 'NF{NF-=2}1' FS='-' OFS='-' ; done ) | sort -u > ${RPM_PKGS}_$RELEASE
		cat ${RPM_PKGS}_$RELEASE
	fi
	echo "$(date -u ) - choosing package to be build."
	local PKG=""
	for PKG in $(sort -R ${RPM_PKGS}_$RELEASE) ; do
		# build package if it has never build or at least $MIN_AGE days ago
		if [ ! -d $BASE/rpms/$RELEASE/$ARCH/$PKG ] || [ $DUMMY -nt $BASE/rpms/$RELEASE/$ARCH/$PKG ] ; then
			SRCPACKAGE=$PKG
			echo "$(date -u ) - building package $PKG from '$RELEASE' on '$ARCH' now..."
			# very simple locking…
			mkdir -p $BASE/rpms/$RELEASE/$ARCH/$PKG
			touch $BASE/rpms/$RELEASE/$ARCH/$PKG
			# break out of the loop and then out of this function too,
			# to build this package…
			break
		fi
	done
	rm $DUMMY > /dev/null
	if [ -z $SRCPACKAGE ] ; then
		echo "$(date -u ) - no package found to be build, sleeping 6h."
		for i in $(seq 1 12) ; do
			sleep 30m
			echo "$(date -u ) - still sleeping..."
		done
		echo "$(date -u ) - exiting cleanly now."
		exit 0
	fi
}

first_build() {
	echo "============================================================================="
	echo "Building for $RELEASE ($ARCH) on $(hostname -f) now."
	echo "Source package: ${SRCPACKAGE}"
	echo "Date:           $(date -u)"
	echo "============================================================================="
	set -x
	update_mock
	download_package
	local RESULTDIR="/tmp/$SRCPACKAGE-$(basename $TMPDIR)"
	local LOG=$TMPDIR/b1/$SRCPACKAGE/build1.log
	# nicely run mock with a timeout of $TIMEOUT hours
	timeout -k $TIMEOUT.1h ${TIMEOUT}h /usr/bin/ionice -c 3 /usr/bin/nice \
		mock -r $RELEASE-$ARCH --uniqueext=$UNIQUEEXT --resultdir=$RESULTDIR --cleanup-after -v --rebuild $SRC_RPM 2>&1 | tee -a $LOG
	PRESULT=${PIPESTATUS[0]}
	if [ $PRESULT -eq 124 ] ; then
		echo "$(date -u) - mock was killed by timeout after ${TIMEOUT}h." | tee -a $LOG
	fi
	if ! "$DEBUG" ; then set +x ; fi
}

second_build() {
	echo "============================================================================="
	echo "Re-Building for $RELEASE ($ARCH) on $(hostname -f) now."
	echo "Source package: ${SRCPACKAGE}"
	echo "Date:           $(date -u)"
	echo "============================================================================="
	set -x
	update_mock
	download_package
	local RESULTDIR="/tmp/$SRCPACKAGE-$(basename $TMPDIR)"
	local LOG=$TMPDIR/b2/$SRCPACKAGE/build2.log
	# NEW_NUM_CPU=$(echo $NUM_CPU-1|bc)
        # nicely run mock with a timeout of $TIMEOUT hours
        timeout -k $TIMEOUT.1h ${TIMEOUT}h /usr/bin/ionice -c 3 /usr/bin/nice \
		mock -r $RELEASE-$ARCH --uniqueext=$UNIQUEEXT --resultdir=$RESULTDIR --cleanup-after -v --rebuild $SRC_RPM 2>&1 | tee -a $LOG
	PRESULT=${PIPESTATUS[0]}
	if [ $PRESULT -eq 124 ] ; then
		echo "$(date -u) - mock was killed by timeout after ${TIMEOUT}h." | tee -a $LOG
	fi
	if ! "$DEBUG" ; then set +x ; fi
}

remote_build() {
	local BUILDNR=$1
	local NODE=$RPM_BUILD_NODE
	local FQDN=$NODE.debian.net
	local PORT=22
	set +e
	ssh -p $PORT $FQDN /bin/true
	RESULT=$?
	# abort job if host is down
	if [ $RESULT -ne 0 ] ; then
		SLEEPTIME=$(echo "$BUILDNR*$BUILDNR*5"|bc)
		echo "$(date -u) - $NODE seems to be down, sleeping ${SLEEPTIME}min before aborting this job."
		sleep ${SLEEPTIME}m
		exec /srv/jenkins/bin/abort.sh
	fi
	ssh -p $PORT $FQDN /srv/jenkins/bin/reproducible_build_rpm.sh $BUILDNR $RELEASE $ARCH $UNIQUEEXT ${SRCPACKAGE} ${TMPDIR}
	RESULT=$?
	if [ $RESULT -ne 0 ] ; then
		ssh -p $PORT $FQDN "rm -r $TMPDIR" || true
		handle_remote_error "with exit code $RESULT from $NODE for build #$BUILDNR for ${SRCPACKAGE} from $RELEASE ($ARCH)"
	fi
	rsync -e "ssh -p $PORT" -r $FQDN:$TMPDIR/b$BUILDNR $TMPDIR/
	RESULT=$?
	if [ $RESULT -ne 0 ] ; then
		echo "$(date -u ) - rsync from $NODE failed, sleeping 2m before re-trying..."
		sleep 2m
		rsync -e "ssh -p $PORT" -r $FQDN:$TMPDIR/b$BUILDNR $TMPDIR/
		RESULT=$?
		if [ $RESULT -ne 0 ] ; then
			handle_remote_error "when rsyncing remote build #$BUILDNR results from $NODE"
		fi
	fi
	ls -lR $TMPDIR
	ssh -p $PORT $FQDN "rm -r $TMPDIR"
	set -e
}

#
# below is what controls the world
#

TMPDIR=$(mktemp --tmpdir=/srv/reproducible-results -d -t rbuild-rpm-XXXXXXXX)  # where everything actually happens
trap cleanup_all INT TERM EXIT
cd $TMPDIR

TIMEOUT=8	# maximum time in hours for a single build
DATE=$(date -u +'%Y-%m-%d %H:%M')
START=$(date +'%s')
DUMMY=$(mktemp -t rpm-dummy-XXXXXXXX)
RPM_STAMPS=/srv/reproducible-results/.rpm_stamp

#
# determine mode
#
if [ "$1" = "1" ] || [ "$1" = "2" ] ; then
	MODE="$1"
	RELEASE="$2"
	ARCH="$3"
	UNIQUEEXT="$4"
	SRCPACKAGE="$5"
	TMPDIR="$6"
	[ -d $TMPDIR ] || mkdir -p $TMPDIR
	cd $TMPDIR
	mkdir -p b$MODE/$SRCPACKAGE
	if [ "$MODE" = "1" ] ; then
		first_build
	else
		second_build
	fi
	# preserve results and delete build directory
	mv -v /tmp/$SRCPACKAGE-$(basename $TMPDIR)/*.rpm $TMPDIR/b$MODE/$SRCPACKAGE/ || ls /tmp/$SRCPACKAGE-$(basename $TMPDIR)/
	rm -r /tmp/$SRCPACKAGE-$(basename $TMPDIR)/
	echo "$(date -u) - build #$MODE for $SRCPACKAGE on $HOSTNAME done."
	exit 0
fi
MODE="master"

#
# main - only used in master-mode
#
delay_start # randomize start times
# first, we need to choose a package…
RELEASE="$1"
ARCH="$2"
UNIQUEEXT="mock${JOB_NAME#reproducible_builder_${RELEASE}_$ARCH}"
SRCPACKAGE=""	# package name
SRC_RPM=""	# src rpm file name
#update_mock # FIXME: we dont have to run mock on the main node yet, but we will need at least have to update yum there…
choose_package
# build package twice
mkdir b1 b2
remote_build 1
# only do the 2nd build if the 1st produced results
if [ ! -z "$(ls $TMPDIR/b1/$SRCPACKAGE/*.rpm 2>/dev/null|| true)" ] ; then
	remote_build 2
	# run diffoscope on the results
	TIMEOUT="30m"
	DIFFOSCOPE="$(schroot --directory /tmp -c source:jenkins-reproducible-${DBDSUITE}-diffoscope diffoscope -- --version 2>&1)"
	echo "$(date -u) - Running $DIFFOSCOPE now..."
	cd $TMPDIR/b1/$SRCPACKAGE
	for ARTIFACT in *.rpm ; do
		[ -f $ARTIFACT ] || continue
		call_diffoscope $SRCPACKAGE $ARTIFACT
		# publish page
		if [ -f $TMPDIR/$SRCPACKAGE/$ARTIFACT.html ] ; then
			cp $TMPDIR/$SRCPACKAGE/$ARTIFACT.html $BASE/rpms/$RELEASE/$ARCH/$SRCPACKAGE/
		fi
	done
fi
# publish logs
cd $TMPDIR/b1/$SRCPACKAGE
cp build1.log $BASE/rpms/$RELEASE/$ARCH/$SRCPACKAGE/
[ ! -f $TMPDIR/b2/$SRCPACKAGE/build2.log ] || cp $TMPDIR/b2/$SRCPACKAGE/build2.log $BASE/rpms/$RELEASE/$ARCH/$SRCPACKAGE/
echo "$(date -u) - $REPRODUCIBLE_URL/rpms/$RELEASE/$ARCH/$SRCPACKAGE/ updated."

cd
cleanup_all
trap - INT TERM EXIT

