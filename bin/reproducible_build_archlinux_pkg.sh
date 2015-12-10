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
	# delete session if it still exists
	if [ "$MODE" != "master" ] ; then
		schroot --end-session -c arch-$SRCPACKAGE-$(basename $TMPDIR) > /dev/null 2>&1 || true
	fi
	# delete makepkg build dir
	if [ ! -z $SRCPACKAGE ] && [ -d /tmp/$SRCPACKAGE-$(basename $TMPDIR) ] ; then
		rm -r /tmp/$SRCPACKAGE-$(basename $TMPDIR)
	fi
	# delete main work dir (only on master)
	if [ "$MODE" = "master" ] ; then
		rm $TMPDIR -r
		echo "$(date -u) - $TMPDIR deleted."
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
	echo "Building ${SRCPACKAGE} for Arch Linux on $(hostname -f) now."
	echo "Date:     $(date)"
	echo "Date UTC: $(date -u)"
	echo "============================================================================="
	set -x
	local SESSION="arch-$SRCPACKAGE-$(basename $TMPDIR)"
	local BUILDDIR="/tmp/$SRCPACKAGE-$(basename $TMPDIR)"
	local LOG=$TMPDIR/b1/$SRCPACKAGE/build1.log
	schroot --begin-session --session-name=$SESSION -c jenkins-reproducible-arch
	echo "MAKEFLAGS=-j$NUM_CPU" | schroot --run-session -c $SESSION --directory /tmp -u root -- tee -a /etc/makepkg.conf
	schroot --run-session -c $SESSION --directory /tmp -- mkdir $BUILDDIR
	schroot --run-session -c $SESSION --directory /tmp -- cp -r /var/abs/core/$SRCPACKAGE $BUILDDIR/
	# just set timezone in the 1st build
	echo 'export TZ="/usr/share/zoneinfo/Etc/GMT+12"' | schroot --run-session -c $SESSION --directory /tmp -- tee -a /var/lib/jenkins/.bashrc
	# nicely run makepkg with a timeout of 4h
	timeout -k 4.1h 4h /usr/bin/ionice -c 3 /usr/bin/nice \
		schroot --run-session -c $SESSION --directory $BUILDDIR/$SRCPACKAGE -- bash -l -c 'makepkg --syncdeps --noconfirm --skippgpcheck 2>&1' | tee -a $LOG
	PRESULT=${PIPESTATUS[0]}
	if [ $PRESULT -eq 124 ] ; then
		echo "$(date -u) - makepkg was killed by timeout after 4h." | tee -a $LOG
	fi
	schroot --end-session -c $SESSION
	if ! "$DEBUG" ; then set +x ; fi
}

second_build() {
	echo "============================================================================="
	echo "Re-Building ${SRCPACKAGE} for Arch Linux on $(hostname -f) now."
	echo "Date:     $(date)"
	echo "Date UTC: $(date -u)"
	echo "============================================================================="
	set -x
	local SESSION="arch-$SRCPACKAGE-$(basename $TMPDIR)"
	local BUILDDIR="/tmp/$SRCPACKAGE-$(basename $TMPDIR)"
	local LOG=$TMPDIR/b2/$SRCPACKAGE/build2.log
	NEW_NUM_CPU=$(echo $NUM_CPU-1|bc)
	schroot --begin-session --session-name=$SESSION -c jenkins-reproducible-arch
	echo "MAKEFLAGS=-j$NEW_NUM_CPU" | schroot --run-session -c $SESSION --directory /tmp -u root -- tee -a /etc/makepkg.conf
	schroot --run-session -c $SESSION --directory /tmp -- mkdir $BUILDDIR
	schroot --run-session -c $SESSION --directory /tmp -- cp -r /var/abs/core/$SRCPACKAGE $BUILDDIR/
	# add more variations in the 2nd build: TZ, LANG, LC_ALL, umask
	schroot --run-session -c $SESSION --directory /tmp -- tee -a /var/lib/jenkins/.bashrc <<-__END__
	export TZ="/usr/share/zoneinfo/Etc/GMT-14"
	export LANG="fr_CH.UTF-8"
	export LC_ALL="fr_CH.UTF-8"
	umask 0002
	__END__
	# nicely run makepkg with a timeout of 4h
	timeout -k 4.1h 4h /usr/bin/ionice -c 3 /usr/bin/nice \
		schroot --run-session -c $SESSION --directory $BUILDDIR/$SRCPACKAGE -- bash -l -c 'makepkg --syncdeps --noconfirm --skippgpcheck 2>&1' | tee -a $LOG
	PRESULT=${PIPESTATUS[0]}
	if [ $PRESULT -eq 124 ] ; then
		echo "$(date -u) - makepkg was killed by timeout after 4h." | tee -a $LOG
	fi
	schroot --end-session -c $SESSION
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
	ssh -p $PORT $NODE /srv/jenkins/bin/reproducible_build_archlinux_pkg.sh $BUILDNR ${SRCPACKAGE} ${TMPDIR}
	RESULT=$?
	if [ $RESULT -ne 0 ] ; then
		ssh -p $PORT $NODE "rm -r $TMPDIR" || true
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

#
# below is what controls the world
#

TMPDIR=$(mktemp --tmpdir=/srv/reproducible-results -d)  # where everything actually happens
trap cleanup_all INT TERM EXIT
cd $TMPDIR

DATE=$(date -u +'%Y-%m-%d %H:%M')
START=$(date +'%s')
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
	mkdir -p b$MODE/$SRCPACKAGE
	if [ "$MODE" = "1" ] ; then
		first_build
	else
		second_build
	fi
	# preserve results and delete build directory
	mv -v /tmp/$SRCPACKAGE-$(basename $TMPDIR)/$SRCPACKAGE/*.pkg.tar.xz $TMPDIR/b$MODE/$SRCPACKAGE/ || ls /tmp/$SRCPACKAGE-$(basename $TMPDIR)/$SRCPACKAGE/
	rm -r /tmp/$SRCPACKAGE-$(basename $TMPDIR)/
	echo "$(date -u) - build #$MODE for $SRCPACKAGE on $HOSTNAME done."
	exit 0
fi

#
# main - only used in master-mode
#
delay_start # randomize start times
# first, we need to choose a package…
#SESSION="arch-scheduler-$RANDOM"
#schroot --begin-session --session-name=$SESSION -c jenkins-reproducible-arch
#PACKAGES="$(schroot --run-session -c $SESSION --directory /var/abs/core -- ls -1|sort -R|xargs echo)"
#schroot --end-session -c $SESSION
#SRCPACKAGE=""
PACKAGES="acl archlinux-keyring attr autoconf automake b43-fwcutter bash binutils bison bridge-utils btrfs-progs bzip2 ca-certificates ca-certificates-cacert coreutils cracklib crda cronie cryptsetup curl dash db dbus dhcpcd dialog diffutils ding-libs dmraid dnssec-anchors dosfstools e2fsprogs ed efibootmgr efivar elfutils expat fakeroot file filesystem findutils flex gawk gcc gdbm gettext glib2 glibc gmp gnupg gnutls gpgme gpm grep groff grub gssproxy gzip hdparm hwids iana-etc ifenslave inetutils iproute2 iptables iputils ipw2100-fw ipw2200-fw isdn4k-utils iw jfsutils kbd keyutils kmod krb5 ldns less libaio libarchive libassuan libcap libedit libevent libffi libgcrypt libgpg-error libgssglue libidn libksba libmpc libnl libpcap libpipeline librpcsecgss libsasl libseccomp libssh2 libtasn1 libtirpc libtool libunistring libusb licenses links linux linux-api-headers linux-atm linux-firmware linux-lts logrotate lvm2 lz4 lzo m4 make man-db man-pages mdadm mkinitcpio mkinitcpio-busybox mkinitcpio-nfs-utils mlocate mpfr nano ncurses net-tools netctl nettle nfs-utils nfsidmap nilfs-utils npth nspr nss openldap openresolv openssh openssl openvpn p11-kit pacman pacman-mirrorlist pam pambase patch pciutils pcmciautils pcre perl pinentry pkg-config popt ppp pptpclient procinfo-ng procps-ng psmisc pth readline reiserfsprogs rfkill rpcbind run-parts s-nail sdparm sed shadow sqlite sudo sysfsutils syslinux systemd tar texinfo thin-provisioning-tools traceroute tzdata usbutils util-linux vi which wireless-regdb wireless_tools wpa_actiond wpa_supplicant xfsprogs xinetd xz zd1211-firmware zlib" # this is hard coded here, because of running jobs on remote nodes, basically… WIP :)
for PKG in $PACKAGES ; do
	# build package if it has never build or at least a week ago
	if [ ! -d $BASE/archlinux/$PKG ] || [ ! -z $(find $BASE/archlinux/ -name $PKG -mtime +6) ] ; then
		SRCPACKAGE=$PKG
		echo "Building $PKG now..."
		# very simple locking…
		mkdir -p $BASE/archlinux/$PKG
		touch $BASE/archlinux/$PKG
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
# build package twice
mkdir b1 b2
remote_build 1
# only do the 2nd build if the 1st produced some results
if [ ! -z "$(ls $TMPDIR/b1/$SRCPACKAGE/*.pkg.tar.xz 2>/dev/null|| true)" ] ; then
	remote_build 2
	# run diffoscope on the results
	TIMEOUT="30m"
	DIFFOSCOPE="$(schroot --directory /tmp -c source:jenkins-reproducible-${DBDSUITE}-diffoscope diffoscope -- --version 2>&1)"
	echo "$(date -u) - Running $DIFFOSCOPE now..."
	cd $TMPDIR/b1/$SRCPACKAGE
	for ARTIFACT in *.pkg.tar.xz ; do
		[ -f $ARTIFACT ] || continue
		call_diffoscope $SRCPACKAGE $ARTIFACT
		# publish page
		if [ -f $TMPDIR/$SRCPACKAGE/$ARTIFACT.html ] ; then
			cp $TMPDIR/$SRCPACKAGE/$ARTIFACT.html $BASE/archlinux/$SRCPACKAGE/
		fi
	done
fi
# publish logs
cd $TMPDIR/b1/$SRCPACKAGE
cp build1.log $BASE/archlinux/$SRCPACKAGE/
[ ! -f $TMPDIR/b2/$SRCPACKAGE/build2.log ] || cp $TMPDIR/b2/$SRCPACKAGE/build2.log $BASE/archlinux/$SRCPACKAGE/
echo "$(date -u) - $REPRODUCIBLE_URL/archlinux/$SRCPACKAGE/ updated."

cd
cleanup_all
trap - INT TERM EXIT

