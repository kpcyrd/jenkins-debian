#!/bin/bash

# Copyright 2014 Holger Levsen <holger@layer-acht.org>
# released under the GPLv=2

common_cleanup(){
	echo "$(date) - $0 stopped running as $TTT, which will now be removed."
	rm -f $TTT
}

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
	# run ourself with the same parameter as we are running
	# but run a copy from /tmp so that the source can be updated
	# (Running shell scripts fail weirdly when overwritten when running,
	#  this hack makes it possible to overwrite long running scripts
	#  anytime...)
	# (setsid is not related to this hack. see commit log for 24deda5a8 it.)
	echo "$(date) - start running \"$0\" as \"$TTT\" using \"$@\" as arguments."
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

