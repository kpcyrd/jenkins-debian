#!/bin/bash

# Copyright 2014-2015 Holger Levsen <holger@layer-acht.org>
# released under the GPLv=2

DEBUG=false
. /srv/jenkins/bin/common-functions.sh
common_init "$@"

cleanup_all() {
	sudo rm -rf --one-file-system $TMPDIR
}

TMPDIR=$(mktemp --tmpdir=/srv/live-build -d)
trap cleanup_all INT TERM EXIT

cd $TMPDIR

# $1 is used for the hostname and username
# $2 is standalone...
lb config --distribution jessie --bootappend-live "boot=live config hostname=$1 username=$1"
case "$2" in
	standalone)	echo education-standalone > config/package-lists/live.list.chroot
			;;
	*)		;;
esac
lb build
ls -la *.iso || true
mkdir -p /srv/live-build/results
cp *.iso /srv/live-build/results
# FIXME: use proper filenames

cleanup_all
trap - INT TERM EXIT

