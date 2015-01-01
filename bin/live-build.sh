#!/bin/bash

# Copyright 2014-2015 Holger Levsen <holger@layer-acht.org>
# released under the GPLv=2

DEBUG=false
. /srv/jenkins/bin/common-functions.sh
common_init "$@"

cleanup_all() {
	rm -r $TMPDIR
}

TMPDIR=$(mktemp --tmpdir=/srv/live-build -d)
trap cleanup_all INT TERM EXIT

cd $TMPDIR
# build an debian-edu .iso for now...
# $1 is debian-edu
# $2 is standalone...
# FIXME: do debian images too
lb config --distribution jessie --bootappend-live "boot=live config hostname=debian-edu username=debian-edu"
echo education-standalone > config/package-lists/live.list.chroot
lb build
ls -la *.iso || true
mkdir -p /srv/live-build/results
cp *.iso /srv/live-build/results
# FIXME: use subdir there... (shared with downloaded .isos?)

cleanup_all
trap - INT TERM EXIT

