#!/bin/bash

# Copyright 2014-2016 Holger Levsen <holger@layer-acht.org>
# released under the GPLv=2

common_cleanup() {
	echo "$(date -u) - $0 stopped running as $TTT, which will now be removed."
	rm -f $TTT
}

abort_if_bug_is_still_open() {
	local TMPFILE=$(mktemp --tmpdir=/tmp jenkins-bugcheck-XXXXXXX)
	bts status $1 fields:done > $TMPFILE || true
	# if we get a valid response…
	if [ ! -z "$(grep done $TMPFILE)" ] ; then
		# if the bug is not done (by some email address containing a @)
		if [ -z "$(grep "@" $TMPFILE)" ] ; then
			rm $TMPFILE
			echo
			echo
			echo "########################################################################"
			echo "#                                                                      #"
			echo "#   https://bugs.debian.org/$1 is still open, aborting this job.   #"
			echo "#                                                                      #"
			echo "########################################################################"
			echo
			echo
			echo
			echo
			exec /srv/jenkins/bin/abort.sh
			exit 0
		fi
	fi
	rm $TMPFILE
}

#
# run ourself with the same parameter as we are running
# but run a copy from /tmp so that the source can be updated
# (Running shell scripts fail weirdly when overwritten when running,
#  this hack makes it possible to overwrite long running scripts
#  anytime...)
#
common_init() {
# check whether this script has been started from /tmp already
if [ "${0:0:5}" != "/tmp/" ] ; then
	# check that we are not root
	if [ $(id -u) -eq 0 ] ; then
		echo "Do not run this as root."
		exit 1
	fi
	# abort certain jobs if we know they will fail due to certain bugs…
	BLOCKER=848422
	case $JOB_NAME in
		#lintian-tests_sid)
		#	abort_if_bug_is_still_open $BLOCKER ;;
		#haskell-package-plan)
		#	abort_if_bug_is_still_open $BLOCKER ;;
		#edu-packages_sid*)
		#	abort_if_bug_is_still_open $BLOCKER ;;
		#reproducible_*_from_git_master)
		#	abort_if_bug_is_still_open $BLOCKER ;;
		#chroot-installation_sid_install_education*)
		#	abort_if_bug_is_still_open $BLOCKER ;;
		#chroot-installation_stretch_install_education-*_upgrade_to_sid)
		#	abort_if_bug_is_still_open $BLOCKER ;;
		*) ;;
	esac
	# mktemp some place for us...
	TTT=$(mktemp --tmpdir=/tmp jenkins-script-XXXXXXXX)
	# prepare cleanup
	trap common_cleanup INT TERM EXIT
	# cp $0 to /tmp and run it from there
	cp $0 $TTT
	chmod +x $TTT
	echo "===================================================================================="
	echo
	echo "$(date -u) - running $0 ($JOB_NAME) on $(hostname) now."
	echo
	echo "To learn to understand this, git clone https://anonscm.debian.org/git/qa/jenkins.debian.net.git"
	echo "and then have a look at the files README, INSTALL, CONTRIBUTING and maybe TODO."
	echo
	echo "This invocation of this script, which is located in bin/$(basename $0),"
	echo "has been called using \"$@\" as arguments." 
	echo
	echo "Please send technical feedback about jenkins to qa-jenkins-dev@lists.alioth.debian.org,"
	echo "or as a bug against the 'jenkins.debian.org' pseudo-package,"
	echo "feedback about specific jobs result should go to their respective lists and/or the BTS."
	echo 
	echo "===================================================================================="
	echo "$(date -u) - start running \"$0\" (md5sum $(md5sum $0|cut -d ' ' -f1)) as \"$TTT\" on $(hostname)."
	echo
	# this is the "hack": call ourself as a copy in /tmp again
	$TTT "$@"
	exit $?
	# cleanup is done automatically via trap
else
	# this directory resides on tmpfs, so it might be gone after reboots...
	mkdir -p /srv/workspace/chroots
	# default settings used for the jenkins.debian.net environment
	if [ -z "$LC_ALL" ]; then
		export LC_ALL=C.UTF-8
	fi

	if [ -z "$MIRROR" ]; then
		case $HOSTNAME in
			jenkins|jenkins-test-vm|profitbricks-build*)
				export MIRROR=http://ftp.de.debian.org/debian ;;
			bbx15|bpi0|cb3*|cbxi4*|hb0|wbq0|odxu4*|odu3*|wbd0|rpi2*|ff2*|ff4*|opi2*|jtk1*)
				export MIRROR=http://ftp.us.debian.org/debian ;;
			codethink*)
				export MIRROR=http://ftp.uk.debian.org/debian ;;
			spectrum)
				export MIRROR=none ;;
			*)
				echo "unsupported host, exiting." ; exit 1 ;;
		esac
	fi
	if [ -z "$http_proxy" ]; then
		case $HOSTNAME in
			jenkins|jenkins-test-vm|profitbricks-build*|codethink*)
				export http_proxy="http://localhost:3128" ;;
			bbx15|bpi0|cb3*|cbxi4*|hb0|wbq0|odxu4*|odu3*|wbd0|rpi2*|ff2*|ff4*|opi2*|jtk1*)
				export http_proxy="http://10.0.0.15:8000/" ;;
			spectrum)
				export MIRROR=none ;;
			*)
				echo "unsupported host, exiting." ; exit 1 ;;
		esac
	fi
	if [ -z "$CHROOT_BASE" ]; then
		export CHROOT_BASE=/chroots
	fi
	if [ -z "$SCHROOT_BASE" ]; then
		export SCHROOT_BASE=/schroots
	fi
	if [ ! -d "$SCHROOT_BASE" ]; then
		echo "Directory $SCHROOT_BASE does not exist, aborting."
		exit 1
	fi
	# use these settings in the scripts in the (s)chroots too
	export SCRIPT_HEADER="#!/bin/bash
	if $DEBUG ; then
		set -x
	fi
	set -e
	export DEBIAN_FRONTEND=noninteractive
	export LC_ALL=$LC_ALL
	export http_proxy=$http_proxy
	export MIRROR=$MIRROR"
	# be more verbose, maybe
	if $DEBUG ; then
		export
		set -x
	fi
	set -e
fi
}

publish_changes_to_userContent() {
	echo "Extracting contents from .deb files..."
	CHANGES=$1
	CHANNEL=$2
	SRCPKG=$(basename $CHANGES | cut -d "_" -f1)
	if [ -z "$SRCPKG" ] ; then
		exit 1
	fi
	VERSION=$(basename $CHANGES | cut -d "_" -f2)
	TARGET="/var/lib/jenkins/userContent/$SRCPKG"
	NEW_CONTENT=$(mktemp -d -t new-content-XXXXXXXX)
	for DEB in $(dcmd --deb $CHANGES) ; do
		dpkg --extract $DEB ${NEW_CONTENT} 2>/dev/null
	done
	rm -rf $TARGET
	mkdir $TARGET
	mv ${NEW_CONTENT}/usr/share/doc/${SRCPKG}-* $TARGET/
	rm -r ${NEW_CONTENT}
	if [ -z "$3" ] ; then
		touch "$TARGET/${VERSION}"
		FROM=""
	else
		touch "$TARGET/${VERSION}_$3"
		FROM=" from $3"
	fi
	MESSAGE="https://jenkins.debian.net/userContent/$SRCPKG/ has been updated${FROM}."
	echo
	echo $MESSAGE
	echo
	if [ ! -z "$CHANNEL" ] ; then
		kgb-client --conf /srv/jenkins/kgb/$CHANNEL.conf --relay-msg "$MESSAGE"
	fi
}

cleanup_schroot_sessions() {
	echo
	local RESULT=""
	for loop in $(seq 0 40) ; do
		# first, check if no process using "schroot" is running, if thats the case, loop through all schroot sessions:
		# arch sessions are ignored, because they are handled properly
		pgrep -f "schroot --directory" || for i in $(schroot --all-sessions -l |grep -v "session:jenkins-reproducible-archlinux"||true) ; do
			# then, check that schroot is still not run, and then delete the session
			if [ -z $i ] ; then
				continue
			fi
			pgrep -f "schroot --directory" || schroot -e -c $i
		done
		RESULT=$(schroot --all-sessions -l|grep -v "session:jenkins-reproducible-archlinux"||true)
		if [ -z "$RESULT" ] ; then
			echo "No schroot sessions in use atm..."
			echo
			break
		fi
		echo "$(date -u) - schroot session cleanup loop $loop"
		sleep 15
	done
	echo
}

