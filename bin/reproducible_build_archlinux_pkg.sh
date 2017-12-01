#!/bin/bash

# Copyright 2015-2017 Holger Levsen <holger@layer-acht.org>
#                2017 kpcyrd <git@rxv.cc>
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
		schroot --end-session -c archlinux-$SRCPACKAGE-$(basename $TMPDIR) > /dev/null 2>&1 || true
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
	cleanup_all
	exec /srv/jenkins/bin/abort.sh
	exit 0
}

choose_package() {
	echo "$(date -u ) - choosing package to be build."
	local REPO
	local PKG
	for REPO in $(echo $ARCHLINUX_REPOS | sed -s "s# #\n#g" | sort -R | xargs echo ); do
		# try to find packages which have been triggered
		for PKG in $(cat ${ARCHLINUX_PKGS}_$REPO | cut -d ' ' -f1 | sort -R | xargs echo ) ; do
			# if triggered...
			if [ -f $BASE/archlinux/$REPO/$PKG/pkg.needs_build ] ; then
				REPOSITORY=$REPO
				SRCPACKAGE=$PKG
				# break out of the loop (and then out of the next loop too...)
				break
			fi
		done
		if [ ! -z "$SRCPACKAGE" ] ; then
			break
		fi
	done
	if [ -z "$SRCPACKAGE" ] ; then
		for REPO in $(echo $ARCHLINUX_REPOS | sed -s "s# #\n#g" | sort -R | xargs echo ); do
			# trz to find packages which never been built before
			for PKG in $(cat ${ARCHLINUX_PKGS}_$REPO | cut -d ' ' -f1 | sort -R | xargs echo ) ; do
				# if new...
				if [ ! -d $BASE/archlinux/$REPO/$PKG ] ; then
					REPOSITORY=$REPO
					SRCPACKAGE=$PKG
					# break out of the loop (and then out of the next loop too...)
					break
				fi
			done
			# again, if we broke out of the previous loop we have choosen a package
			if [ ! -z "$SRCPACKAGE" ] ; then
				break
			fi
		done
	fi
	if [ -z $SRCPACKAGE ] ; then
		echo "$(date -u ) - no package found to be build, sleeping 6h."
		for i in $(seq 1 12) ; do
			sleep 30m
			echo "$(date -u ) - still sleeping..."
		done
		echo "$(date -u ) - exiting cleanly now."
		exit 0
	fi
	echo "$(date -u ) - building package $SRCPACKAGE from '$REPOSITORY' now..."
	# very simple locking…
	mkdir -p $BASE/archlinux/$REPOSITORY/$SRCPACKAGE
	[ ! -f $BASE/archlinux/$REPO/$SRCPACKAGE/pkg.needs_build ] || rm $BASE/archlinux/$REPO/$SRCPACKAGE/pkg.needs_build
}

first_build() {
	echo "============================================================================="
	echo "Building for Arch Linux on $(hostname -f) now."
	echo "Source package: ${SRCPACKAGE}"
	echo "Repository:     $REPOSITORY"
	echo "Date:           $(date -u)"
	echo "============================================================================="
	local SESSION="archlinux-$SRCPACKAGE-$(basename $TMPDIR)"
	local BUILDDIR="/tmp/$SRCPACKAGE-$(basename $TMPDIR)"
	local LOG=$TMPDIR/b1/$SRCPACKAGE/build1.log
	local FUTURE_STATE="disabled"
	local MAKEPKG_ENV_VARS="SOURCE_DATE_EPOCH='$SOURCE_DATE_EPOCH'"
	if [ "$(hostname -f)" = "profitbricks-build4-amd64" ] ; then
		FUTURE_STATE="enabled"
		MAKEPKG_ENV_VARS="$MAKEPKG_ENV_VARS GIT_SSL_NO_VERIFY=1"
	fi
	echo "Future:            $FUTURE_STATE"
	echo "SOURCE_DATE_EPOCH: $SOURCE_DATE_EPOCH"
	echo "makepkg env:       $MAKEPKG_ENV_VARS"
	echo "============================================================================="
	schroot --begin-session --session-name=$SESSION -c jenkins-reproducible-archlinux
	echo "MAKEFLAGS=-j$NUM_CPU" | schroot --run-session -c $SESSION --directory /tmp -u root -- tee -a /etc/makepkg.conf
	schroot --run-session -c $SESSION --directory /tmp -- mkdir $BUILDDIR
	schroot --run-session -c $SESSION --directory "$BUILDDIR" -- env GIT_SSL_NO_VERIFY=1 asp checkout "$SRCPACKAGE" 2>&1 | tee -a $LOG
	# $SRCPACKAGE is actually the binary package
	ACTUAL_SRCPACKAGE=$(ls "$BUILDDIR")
	# just set timezone in the 1st build
	echo 'export TZ="/usr/share/zoneinfo/Etc/GMT+12"' | schroot --run-session -c $SESSION --directory /tmp -- tee -a /var/lib/jenkins/.bashrc
	echo "============================================================================="
	echo "Current configuration values follow:"
	echo "============================================================================="
	schroot --run-session -c $SESSION --directory "$BUILDDIR" -- cat /etc/pacman.conf 2>&1 | tee -a $LOG
	echo "============================================================================="
	schroot --run-session -c $SESSION --directory "$BUILDDIR" -- cat /etc/makepkg.conf 2>&1 | tee -a $LOG
	echo "============================================================================="
	# update before pulling new dependencies
	schroot --run-session -c $SESSION --directory "$BUILDDIR" -- sudo pacman -Syyu --debug --noconfirm 2>&1 | tee -a $LOG
	# log installed packages and used mirrors
	schroot --run-session -c $SESSION --directory "$BUILDDIR" -- grep '^Server' /etc/pacman.d/mirrorlist 2>&1 | tee -a $LOG
	schroot --run-session -c $SESSION --directory "$BUILDDIR" -- pacman -Q 2>&1 | tee -a $LOG
	# TODO: debugging, remove me
	schroot --run-session -c $SESSION --directory "$BUILDDIR" -- pacman -Si gnupg 2>&1 | tee -a $LOG
	# determine the version of the package being build
	source "$BUILDDIR/$ACTUAL_SRCPACKAGE/trunk/PKGBUILD"
	if [ -n "$epoch" ] ; then
		epoch="$epoch:"
	fi
	VERSION="$epoch$pkgver-$pkgrel"
	echo $VERSION > $TMPDIR/b1/$SRCPACKAGE/build1.version
	# nicely run makepkg with a timeout of $TIMEOUT hours
	timeout -k $TIMEOUT.1h ${TIMEOUT}h /usr/bin/ionice -c 3 /usr/bin/nice \
		schroot --run-session -c $SESSION --directory "$BUILDDIR/$ACTUAL_SRCPACKAGE/trunk" -- bash -l -c "$MAKEPKG_ENV_VARS makepkg --syncdeps --noconfirm 2>&1" | tee -a $LOG
	PRESULT=${PIPESTATUS[0]}
	if [ $PRESULT -eq 124 ] ; then
		echo "$(date -u) - makepkg was killed by timeout after ${TIMEOUT}h." | tee -a $LOG
	fi
	schroot --end-session -c $SESSION | tee -a $LOG
	PRESULT=${PIPESTATUS[0]}
	if [ $PRESULT -ne 0 ] ; then
		echo "$(date -u) - could not end schroot session, maybe some processes are still running? Sleeping 60 seconds and trying again…" | tee -a $LOG
		sleep 60
		schroot --end-session -f -c $SESSION | tee -a $LOG
		P2RESULT=${PIPESTATUS[0]}
		if [ $P2RESULT -ne 0 ] ; then
			echo "$(date -u) - could not end schroot session even with force. Sleeping 10 seconds and trying once more…" | tee -a $LOG
			sleep 10
			schroot --end-session -f -c $SESSION | tee -a $LOG
			P3RESULT=${PIPESTATUS[0]}
			if [ $P3RESULT -ne 0 ] ; then
				if [ -n "$(grep 'ERROR: One or more PGP signatures could not be verified' $LOG)" ] ; then
					# abort only
					exit 42
				else
					# fail with notification
					exit 23
				fi
			fi
		fi
	fi
	if ! "$DEBUG" ; then set +x ; fi
}

second_build() {
	echo "============================================================================="
	echo "Re-Building for Arch Linux on $(hostname -f) now."
	echo "Source package: ${SRCPACKAGE}"
	echo "Repository:     $REPOSITORY"
	echo "Date:           $(date -u)"
	echo "============================================================================="
	local SESSION="archlinux-$SRCPACKAGE-$(basename $TMPDIR)"
	local BUILDDIR="/tmp/$SRCPACKAGE-$(basename $TMPDIR)"
	local LOG=$TMPDIR/b2/$SRCPACKAGE/build2.log
	NEW_NUM_CPU=$(echo $NUM_CPU-1|bc)
	local FUTURE_STATE="disabled"
	local MAKEPKG_ENV_VARS="SOURCE_DATE_EPOCH='$SOURCE_DATE_EPOCH'"
	if [ "$(hostname -f)" = "profitbricks-build4-amd64" ] ; then
		FUTURE_STATE="enabled"
		MAKEPKG_ENV_VARS="$MAKEPKG_ENV_VARS GIT_SSL_NO_VERIFY=1"
	fi
	echo "Future:            $FUTURE_STATE"
	echo "SOURCE_DATE_EPOCH: $SOURCE_DATE_EPOCH"
	echo "makepkg env:       $MAKEPKG_ENV_VARS"
	echo "============================================================================="
	schroot --begin-session --session-name=$SESSION -c jenkins-reproducible-archlinux
	echo "MAKEFLAGS=-j$NEW_NUM_CPU" | schroot --run-session -c $SESSION --directory /tmp -u root -- tee -a /etc/makepkg.conf
	schroot --run-session -c $SESSION --directory /tmp -- mkdir $BUILDDIR
	schroot --run-session -c $SESSION --directory "$BUILDDIR" -- env GIT_SSL_NO_VERIFY=1 asp checkout "$SRCPACKAGE" 2>&1 | tee -a $LOG
	# $SRCPACKAGE is actually the binary package
	ACTUAL_SRCPACKAGE=$(ls "$BUILDDIR")
	# add more variations in the 2nd build: TZ, LANG, LC_ALL, umask
	schroot --run-session -c $SESSION --directory /tmp -- tee -a /var/lib/jenkins/.bashrc <<-__END__
	export TZ="/usr/share/zoneinfo/Etc/GMT-14"
	export LANG="fr_CH.UTF-8"
	export LC_ALL="fr_CH.UTF-8"
	umask 0002
	__END__
	echo "============================================================================="
	echo "Current configuration values follow:"
	echo "============================================================================="
	schroot --run-session -c $SESSION --directory "$BUILDDIR" -- cat /etc/pacman.conf 2>&1 | tee -a $LOG
	echo "============================================================================="
	schroot --run-session -c $SESSION --directory "$BUILDDIR" -- cat /etc/makepkg.conf 2>&1 | tee -a $LOG
	echo "============================================================================="
	# update before pulling new dependencies
	schroot --run-session -c $SESSION --directory "$BUILDDIR" -- sudo pacman -Syyu --debug --noconfirm 2>&1 | tee -a $LOG
	# log installed packages and used mirrors
	schroot --run-session -c $SESSION --directory "$BUILDDIR" -- grep '^Server' /etc/pacman.d/mirrorlist 2>&1 | tee -a $LOG
	schroot --run-session -c $SESSION --directory "$BUILDDIR" -- pacman -Q 2>&1 | tee -a $LOG
	# TODO: debugging, remove me
	schroot --run-session -c $SESSION --directory "$BUILDDIR" -- pacman -Si gnupg 2>&1 | tee -a $LOG
	# determine the version of the package being build
	source "$BUILDDIR/$ACTUAL_SRCPACKAGE/trunk/PKGBUILD"
	if [ -n "$epoch" ] ; then
		epoch="$epoch:"
	fi
	VERSION="$epoch$pkgver-$pkgrel"
	echo $VERSION > $TMPDIR/b2/$SRCPACKAGE/build2.version
	# nicely run makepkg with a timeout of $TIMEOUT hours
	timeout -k $TIMEOUT.1h ${TIMEOUT}h /usr/bin/ionice -c 3 /usr/bin/nice \
		schroot --run-session -c $SESSION --directory "$BUILDDIR/$ACTUAL_SRCPACKAGE/trunk" -- bash -l -c "$MAKEPKG_ENV_VARS makepkg --syncdeps --noconfirm 2>&1" | tee -a $LOG
	PRESULT=${PIPESTATUS[0]}
	if [ $PRESULT -eq 124 ] ; then
		echo "$(date -u) - makepkg was killed by timeout after ${TIMEOUT}h." | tee -a $LOG
	fi
	schroot --end-session -c $SESSION | tee -a $LOG
	PRESULT=${PIPESTATUS[0]}
	if [ $PRESULT -ne 0 ] ; then
		echo "$(date -u) - could not end schroot session, maybe some processes are still running? Sleeping 60 seconds and trying again…" | tee -a $LOG
		sleep 60
		schroot --end-session -f -c $SESSION | tee -a $LOG
		P2RESULT=${PIPESTATUS[0]}
		if [ $P2RESULT -ne 0 ] ; then
			echo "$(date -u) - could not end schroot session even with force. Sleeping 10 seconds and trying once more…" | tee -a $LOG
			sleep 10
			schroot --end-session -f -c $SESSION | tee -a $LOG
			P3RESULT=${PIPESTATUS[0]}
			if [ $P3RESULT -ne 0 ] ; then
				exit 23
			fi
		fi
	fi
	if ! "$DEBUG" ; then set +x ; fi
}

remote_build() {
	local BUILDNR=$1
	local NODE=$2
	local FQDN=$NODE.debian.net
	local PORT=22
	set +e
	ssh -o "Batchmode = yes" -p $PORT $FQDN /bin/true
	RESULT=$?
	# abort job if host is down
	if [ $RESULT -ne 0 ] ; then
		SLEEPTIME=$(echo "$BUILDNR*$BUILDNR*5"|bc)
		echo "$(date -u) - $NODE seems to be down, sleeping ${SLEEPTIME}min before aborting this job."
		sleep ${SLEEPTIME}m
		cleanup_all
		exec /srv/jenkins/bin/abort.sh
	fi
	ssh -o "Batchmode = yes" -p $PORT $FQDN /srv/jenkins/bin/reproducible_build_archlinux_pkg.sh $BUILDNR $REPOSITORY ${SRCPACKAGE} ${TMPDIR} ${SOURCE_DATE_EPOCH}
	RESULT=$?
	if [ $RESULT -ne 0 ] ; then
		ssh -o "Batchmode = yes" -p $PORT $FQDN "rm -r $TMPDIR" || true
		if [ $RESULT -eq 23 ] ; then
			echo "$(date -u) - remote job could not end schroot session properly and sent error 23 so we could abort silently."
			cleanup_all
			exec /srv/jenkins/bin/abort.sh
		elif [ $RESULT -eq 42 ] ; then
			echo "$($date -u) - sigh, failure after not being able to verify pgp signatures. work to debug why ahead."
			cleanup_all
			exec /srv/jenkins/bin/abort.sh
		else
			# FIXME: atm this is never reached…
			#cleanup_all
			#handle_remote_error "with exit code $RESULT from $NODE for build #$BUILDNR for ${SRCPACKAGE} from $REPOSITORY"
			echo "Warning: remote build failed with exit code $RESULT from $NODE for build #$BUILDNR for ${SRCPACKAGE} from $REPOSITORY."
		fi
	fi
	rsync -e "ssh -o 'Batchmode = yes' -p $PORT" -r $FQDN:$TMPDIR/b$BUILDNR $TMPDIR/
	RESULT=$?
	if [ $RESULT -ne 0 ] ; then
		echo "$(date -u ) - rsync from $NODE failed, sleeping 2m before re-trying..."
		sleep 2m
		rsync -e "ssh -o 'Batchmode = yes' -p $PORT" -r $FQDN:$TMPDIR/b$BUILDNR $TMPDIR/
		RESULT=$?
		if [ $RESULT -ne 0 ] ; then
			#handle_remote_error "when rsyncing remote build #$BUILDNR results from $NODE"
			echo "Warning: error rsyncing remote build #$BUILDNR results from $NODE."
		fi
	fi
	ls -lR $TMPDIR
	ssh -o "Batchmode = yes" -p $PORT $FQDN "rm -r $TMPDIR"
	set -e
}

#
# below is what controls the world
#
TIMEOUT=12	# maximum time in hours for a single build
DATE=$(date -u +'%Y-%m-%d %H:%M')
START=$(date +'%s')
trap cleanup_all INT TERM EXIT

#
# determine mode
#
if [ "$1" = "" ] ; then
	MODE="master"
	TMPDIR=$(mktemp --tmpdir=/srv/reproducible-results -d -t rbuild-archlinux-XXXXXXXX)  # where everything actually happens
	SOURCE_DATE_EPOCH=$(date +%s)
	cd $TMPDIR
elif [ "$1" = "1" ] || [ "$1" = "2" ] ; then
	MODE="$1"
	REPOSITORY="$2"
	SRCPACKAGE="$3"
	TMPDIR="$4"
	SOURCE_DATE_EPOCH="$5"
	[ -d $TMPDIR ] || mkdir -p $TMPDIR
	cd $TMPDIR
	mkdir -p b$MODE/$SRCPACKAGE
	if [ "$MODE" = "1" ] ; then
		first_build
	else
		second_build
	fi

	# preserve results and delete build directory
	if ! mv -v /tmp/$SRCPACKAGE-$(basename $TMPDIR)/*/trunk/*.pkg.tar.xz $TMPDIR/b$MODE/$SRCPACKAGE/; then
		echo "$(date -u) - build #$MODE for $SRCPACKAGE on $HOSTNAME didn't build a package!"
		mkdir -p $BASE/archlinux/$REPOSITORY/$SRCPACKAGE/
		# copy build$MODE.(log|version) though this is probably useless - FIXME: confirm or disprove
		cp $TMPDIR/b$MODE/$SRCPACKAGE/build$MODE.* $BASE/archlinux/$REPOSITORY/$SRCPACKAGE/
	fi

	rm -r /tmp/$SRCPACKAGE-$(basename $TMPDIR)/
	echo "$(date -u) - build #$MODE for $SRCPACKAGE on $HOSTNAME done."
	exit 0
fi

#
# main - only used in master-mode
#
delay_start # randomize start times
# first, we need to choose a package from a repository…
REPOSITORY=""
SRCPACKAGE=""
VERSION=""
choose_package
# build package twice
mkdir b1 b2
# currently there are two Arch Linux build nodes… let's keep things simple
N1="profitbricks-build3-amd64"
N2="profitbricks-build4-amd64"
# if random number between 0 and 99 is greater than 60…
# (because pb4 is generally less loaded than pb3)
if [ $(( ( $RANDOM % 100 ) )) -gt 60 ] ; then
	NODE1=$N1
	NODE2=$N2
else
	NODE1=$N2
	NODE2=$N1
fi
remote_build 1 ${NODE1}
# only do the 2nd build if the 1st produced results
if [ ! -z "$(ls $TMPDIR/b1/$SRCPACKAGE/*.pkg.tar.xz 2>/dev/null|| true)" ] ; then
	remote_build 2 ${NODE2}
	cd $TMPDIR/b1/$SRCPACKAGE
	for ARTIFACT in *.pkg.tar.xz ; do
		[ -f $ARTIFACT ] || continue
		echo "$(date -u) - comparing results now."
		if diff -q $TMPDIR/b1/$SRCPACKAGE/$ARTIFACT $TMPDIR/b2/$SRCPACKAGE/$ARTIFACT ; then
			echo "$(date -u) - YAY - $SRCPACKAGE/$ARTIFACT build reproducible in our test framework!"
			mkdir -p $BASE/archlinux/$REPOSITORY/$SRCPACKAGE
			tar xJvf $TMPDIR/b1/$SRCPACKAGE/$ARTIFACT .BUILDINFO && mv .BUILDINFO $BASE/archlinux/$REPOSITORY/$SRCPACKAGE/$ARTIFACT-b1.BUILDINFO.txt
			tar xJvf $TMPDIR/b2/$SRCPACKAGE/$ARTIFACT .BUILDINFO && mv .BUILDINFO $BASE/archlinux/$REPOSITORY/$SRCPACKAGE/$ARTIFACT-b2.BUILDINFO.txt
			(
				echo "<html><body><p>$SRCPACKAGE/$ARTIFACT build reproducible in our test framework:<br />"
				(cd $TMPDIR/b1/$SRCPACKAGE ; sha256sum $ARTIFACT)
				echo "<br />"
				(sha256sum $BASE/archlinux/$REPOSITORY/$SRCPACKAGE/$ARTIFACT-b1.BUILDINFO.txt | cut -d " " -f1)
				echo " <a href=\"$ARTIFACT-b1.BUILDINFO.txt\">$ARTIFACT-b1.BUILDINFO.txt</a><br />"
				(sha256sum $BASE/archlinux/$REPOSITORY/$SRCPACKAGE/$ARTIFACT-b2.BUILDINFO.txt | cut -d " " -f1)
				echo " <a href=\"$ARTIFACT-b2.BUILDINFO.txt\">$ARTIFACT-b2.BUILDINFO.txt</a><br />"
				echo "</p></body>"
			) > "$BASE/archlinux/$REPOSITORY/$SRCPACKAGE/$ARTIFACT.html"
		elif [ -f $TMPDIR/b1/$SRCPACKAGE/$ARTIFACT ] && [ -f $TMPDIR/b2/$SRCPACKAGE/$ARTIFACT ] ; then
			# run diffoscope on the results
			TIMEOUT="30m"
			DIFFOSCOPE="$(schroot --directory /tmp -c source:jenkins-reproducible-${DBDSUITE}-diffoscope diffoscope -- --version 2>&1)"
			echo "$(date -u) - Running $DIFFOSCOPE now..."
			call_diffoscope $SRCPACKAGE $ARTIFACT
		fi
		# publish page
		if [ -f $TMPDIR/$SRCPACKAGE/$ARTIFACT.html ] ; then
			cp $TMPDIR/$SRCPACKAGE/$ARTIFACT.html $BASE/archlinux/$REPOSITORY/$SRCPACKAGE/
			irc_message archlinux-reproducible "$REPRODUCIBLE_URL/archlinux/$REPOSITORY/$SRCPACKAGE/$ARTIFACT.html updated unreproducible package."
		fi
	done
else
	echo "$(date -u) - build1 didn't create a package, skipping build2!"
fi
# publish logs
calculate_build_duration
cd $TMPDIR/b1/$SRCPACKAGE
cp build1.log $BASE/archlinux/$REPOSITORY/$SRCPACKAGE/
[ ! -f $TMPDIR/b2/$SRCPACKAGE/build2.log ] || cp $TMPDIR/b2/$SRCPACKAGE/build2.log $BASE/archlinux/$REPOSITORY/$SRCPACKAGE/
echo $DURATION > $BASE/archlinux/$REPOSITORY/$SRCPACKAGE/pkg.build_duration || true
cp build1.version $BASE/archlinux/$REPOSITORY/$SRCPACKAGE/ || true
[ ! -f $TMPDIR/b2/$SRCPACKAGE/build2.version ] || cp $TMPDIR/b2/$SRCPACKAGE/build2.version $BASE/archlinux/$REPOSITORY/$SRCPACKAGE/
echo "$(date -u) - $REPRODUCIBLE_URL/archlinux/$REPOSITORY/$SRCPACKAGE/ updated."
# force update of HTML snipplet in reproducible_html_archlinux.sh
[ ! -f $BASE/archlinux/$REPOSITORY/$SRCPACKAGE/pkg.state ] || rm $BASE/archlinux/$REPOSITORY/$SRCPACKAGE/pkg.state

cd
cleanup_all
trap - INT TERM EXIT

# vim: set sw=0 noet :
