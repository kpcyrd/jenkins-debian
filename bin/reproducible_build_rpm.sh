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
	if [ ! -f $STAMP ] || [ $DUMMY -nt $STAMP ] ; then
		echo "$(date -u ) - updating mock for $RELEASE ($ARCH) on $HOSTNAME now..."
		mock -r $RELEASE-$ARCH --resultdir=. --cleanup-after -v --update 2>&1
		echo "$(date -u ) - mock updated."
		# set the end of reproducible_setup_mock to learn why this is commented out 
		#yum -v check-update
		#echo "$(date -u ) - yum updated."
		touch $STAMP
	else
		echo "$(date -u ) - mock and yum not updated, last update was at $(TZ=UTC ls --full-time $STAMP | cut -d ' ' -f6-7 | cut -d '.' -f1) UTC."
	fi
}

download_package() {
	echo "$(date -u ) - downloading ${SRCPACKAGE} for $RELEASE now."
	yumdownloader --source ${SRCPACKAGE}
	SRC_RPM="$(ls *.src.rpm)"
}

choose_package() {
	echo "$(date -u ) - choosing package to be build."
	local MIN_AGE=6
	# instead of hardcoding the list of packages we can also use something like this to get a list of all packages:
	# yumdownloader --urls --source --releasever=23 '*'
	for PKG in $(echo audit-libs basesystem bash binutils bzip2 bzip2-libs ca-certificates chkconfig coreutils cpio cpp cracklib cracklib-dicts crypto-policies curl cyrus-sasl-lib diffutils dwz elfutils elfutils-default-yama-scope elfutils-libelf elfutils-libs emacs-filesystem expat fedora-release fedora-repos file file-libs filesystem findutils gawk gc gcc gcc-c++ gdb gdbm ghc-srpm-macros glib2 glibc glibc-common glibc-devel glibc-headers gmp gnat-srpm-macros gnupg2 gnutls go-srpm-macros grep groff-base guile gzip info isl kernel-headers keyutils-libs krb5-libs libacl libarchive libassuan libatomic_ops libattr libbabeltrace libblkid libcap libcap-ng libcom_err libcurl libdb libdb-utils libfdisk libffi libgcc libgcrypt libgomp libgpg-error libidn libipt libksba libmetalink libmount libmpc libnghttp2 libpwquality libseccomp libsecret libselinux libsemanage libsepol libsmartcols libssh2 libstdc++ libstdc++-devel libtasn1 libtool-ltdl libunistring libuser libutempter libuuid libverto libxml2 lua lzo make mpfr ncurses ncurses-base ncurses-libs nettle npth nspr nss nss-softokn nss-softokn-freebl nss-sysinit nss-tools nss-util ocaml-srpm-macros openldap openssl-libs p11-kit p11-kit-trust pam patch pcre perl perl-Carp perl-constant perl-Encode perl-Exporter perl-File-Path perl-File-Temp perl-generators perl-Getopt-Long perl-HTTP-Tiny perl-libs perl-macros perl-MIME-Base64 perl-parent perl-PathTools perl-Pod-Escapes perl-podlators perl-Pod-Perldoc perl-Pod-Simple perl-Pod-Usage perl-Scalar-List-Utils perl-Socket perl-srpm-macros perl-Storable perl-Term-ANSIColor perl-Term-Cap perl-Text-ParseWords perl-Text-Tabs+Wrap perl-threads perl-threads-shared perl-Time-HiRes perl-Time-Local perl-Unicode-Normalize pinentry pkgconfig popt python3 python3-libs python3-pip python3-setuptools readline redhat-rpm-config rpm rpm-build rpm-build-libs rpm-libs rpm-plugin-selinux sed setup shadow-utils shared-mime-info sqlite systemd-libs tar tzdata unzip ustr util-linux which xz xz-libs zip zlib | sed -s "s# #\n#g" | sort -R | xargs echo) ; do
		# build package if it has never build or at least $MIN_AGE days ago
		if [ ! -d $BASE/rpms/$RELEASE/$ARCH/$PKG ] || [ ! -z $(find $BASE/rpms/$RELEASE/$ARCH/ -name $PKG -mtime +$MIN_AGE) ] ; then
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
		mock -r $RELEASE-$ARCH --resultdir=$RESULTDIR --cleanup-after -v --rebuild $SRC_RPM 2>&1 | tee -a $LOG
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
		mock -r $RELEASE-$ARCH --resultdir=$RESULTDIR --cleanup-after -v --rebuild $SRC_RPM 2>&1 | tee -a $LOG
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
	ssh -p $PORT $FQDN /srv/jenkins/bin/reproducible_build_rpm.sh $BUILDNR $RELEASE $ARCH ${SRCPACKAGE} ${TMPDIR}
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

TMPDIR=$(mktemp --tmpdir=/srv/reproducible-results -d)  # where everything actually happens
trap cleanup_all INT TERM EXIT
cd $TMPDIR

TIMEOUT=8	# maximum time in hours for a single build
DATE=$(date -u +'%Y-%m-%d %H:%M')
START=$(date +'%s')
DUMMY=$(mktemp -t rpm-dummy-XXXXXXXX)
touch -d "$(date -u -d "6 hours ago" '+%Y-%m-%d %H:%M') UTC" $DUMMY
RPM_STAMPS=/srv/reproducible-results/.rpm_stamp

#
# determine mode
#
if [ "$1" = "1" ] || [ "$1" = "2" ] ; then
	MODE="$1"
	RELEASE="$2"
	ARCH="$3"
	SRCPACKAGE="$4"
	TMPDIR="$5"
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
SRCPACKAGE=""	# package name
SRC_RPM=""	# src rpm file name
# not used yet:
UNIQEEXT="mock_${JOB_NAME#reproducible_builder_${RELEASE}_$ARCH}}"
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

