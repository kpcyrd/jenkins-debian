#!/bin/bash

# Copyright 2015 Holger Levsen <holger@layer-acht.org>
# released under the GPLv=2

DEBUG=false
. /srv/jenkins/bin/common-functions.sh
common_init "$@"

set -e

cleanup_all() {
	set +e
	# preserve screenshots
	[ ! -f screenshot.png ] || mv screenshot.png $WORKSPACE/ || true
	[ ! -f screenshot-thumb.png ] || mv screenshot-thumb.png $WORKSPACE/ || true
	# actual cleanup starts here
	cd
	# delete session if it still exists
	schroot --end-session -c tbb-launcher-$SUITE-$(basename $TMPDIR) > /dev/null 2>&1 || true
	# delete main work dir
	rm $TMPDIR -r
	# kill xvfb
	kill $XPID 2>/dev/null|| true
	# end
	echo "$(date -u) - $TMPDIR deleted. Cleanup done."
}

update_screenshot() {
	xwd -root -silent -display :$SCREEN.0 | xwdtopnm > screenshot.pnm
	pnmtopng screenshot.pnm > screenshot.png
	convert screenshot.png -adaptive-resize 128x96 screenshot-thumb.png
	mv screenshot.png screenshot-thumb.png $WORKSPACE/ || true
}

first_test() {
	set -x
	local SESSION="tbb-launcher-$SUITE-$(basename $TMPDIR)"
	schroot --begin-session --session-name=$SESSION -c jenkins-torbrowser-launcher-$SUITE
	schroot --run-session -c $SESSION --directory /tmp -u root -- mkdir $HOME
	schroot --run-session -c $SESSION --directory /tmp -u root -- chown jenkins:jenkins $HOME
	SCREEN=77
	Xvfb -ac -br -screen 0 1024x768x16 :$SCREEN &
	XPID=$!
	export DISPLAY=":$SCREEN.0"
	timeout -k 12m 11m schroot --run-session -c $SESSION --preserve-environment -- torbrowser-launcher https://www.debian.org &
	for i in $(seq 1 6) ; do
		sleep 1m
		update_screenshot
	done
	schroot --end-session -c $SESSION
	kill $XPID || true
	if ! "$DEBUG" ; then set +x ; fi
}

#
# main
#

TMPDIR=$(mktemp -d)  # where everything actually happens
trap cleanup_all INT TERM EXIT
WORKSPACE=$(pwd)
cd $TMPDIR

SUITE=$1
echo "$(date -u) - testing torbrowser-launcher on $SUITE now."
#
# this is WIP in an early stage
# - test package build from git (todo)
# - test package from the archive (in progress)
# - test updates (todo)
#
first_test

# publish results
mv screenshot.png screenshot-thumb.png $WORKSPACE/

cd
cleanup_all
trap - INT TERM EXIT
echo "$(date -u) - the end."

