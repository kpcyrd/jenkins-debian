#!/bin/bash

# Copyright 2014 Holger Levsen <holger@layer-acht.org>
# released under the GPLv=2

common_cleanup(){
	echo "$(date) - $0 stopped running as $TTT, which will now be removed."
	rm -f $TTT
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
	# mktemp some place for us...
	TTT=$(mktemp --tmpdir=/tmp jenkins-script-XXXXXXXX)
	# prepare cleanup
	trap common_cleanup INT TERM EXIT
	# cp $0 to /tmp and run it from there
	cp $0 $TTT
	chmod +x $TTT
	echo "===================================================================================="
	echo
	echo "$(date) - running job $JOB_NAME now."
	echo
	echo "To understand what this job does, clone git.debian.org/git/qa/jenkins.debian.net.git"
	echo "and then have a look at bin/$(basename $0)"
	echo 
	echo "The script is called using \"$@\" as arguments." 
	echo
	echo "===================================================================================="
	echo
	echo "$(date) - start running \"$0\" as \"$TTT\"."
	# this is the "hack": call ourself as a copy in /tmp again
	# (setsid is not related to this hack. see commit log for 24deda5a8 it.)
	/srv/jenkins/bin/setsid.py $TTT "$@"
	exit $?
	# cleanup is done automatically via trap
else
	# default settings used for the jenkins.debian.net environment
	if [ -z "$LC_ALL" ]; then
		export LC_ALL=C
	fi
	if [ -z "$MIRROR" ]; then
		export MIRROR=http://ftp.de.debian.org/debian
	fi
	if [ -z "$http_proxy" ]; then
		export http_proxy="http://localhost:3128"
	fi
	if [ -z "$CHROOT_BASE" ]; then
		export CHROOT_BASE=/chroots
	fi
	if [ -z "$SCHROOT_BASE" ]; then
		export SCHROOT_BASE=/schroots
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

publish_changes_to_userContent(){
	echo "Extracting contents from .deb files..."
	CHANGES=$1
	CHANNEL=$2
	SRCPKG=$(basename $CHANGES | cut -d "_" -f1)
	if [ -z "$SRCPKG" ] ; then
		exit 1
	fi
	VERSION=$(basename $CHANGES | cut -d "_" -f2)
	TARGET="/var/lib/jenkins/userContent/$SRCPKG"
	NEW_CONTENT=$(mktemp -d)
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

