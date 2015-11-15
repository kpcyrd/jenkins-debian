#!/bin/bash

# Copyright 2015 Holger Levsen <holger@layer-acht.org>
# released under the GPLv=2

DEBUG=false
. /srv/jenkins/bin/common-functions.sh
common_init "$@"

set -e

cleanup_all() {
	set +e
	# kill xvfb and ffmpeg
	kill $XPID $FFMPEGPID 2>/dev/null|| true
	# preserve screenshots
	[ ! -f screenshot.png ] || mv screenshot.png $WORKSPACE/
	[ ! -f screenshot-thumb.png ] || mv screenshot-thumb.png $WORKSPACE/
	[ ! -f test-torbrowser-$SUITE.mpg ] || mv test-torbrowser-$SUITE.mpg $WORKSPACE/
	# delete session if it still exists
	schroot --end-session -c tbb-launcher-$SUITE-$(basename $TMPDIR) > /dev/null 2>&1 || true
	# delete main work dir
	cd
	rm $TMPDIR -r
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
	local SESSION="tbb-launcher-$SUITE-$(basename $TMPDIR)"
	schroot --begin-session --session-name=$SESSION -c jenkins-torbrowser-launcher-$SUITE
	schroot --run-session -c $SESSION --directory /tmp -u root -- mkdir $HOME
	schroot --run-session -c $SESSION --directory /tmp -u root -- chown jenkins:jenkins $HOME
	SCREEN=77
	Xvfb -ac -br -screen 0 1024x768x16 :$SCREEN &
	XPID=$!
	export DISPLAY=":$SCREEN.0"
	export
	timeout -k 12m 11m schroot --run-session -c $SESSION --preserve-environment -- torbrowser-launcher https://www.debian.org &
	ffmpeg -f x11grab -i :$SCREEN.0 test-torbrowser-$SUITE.mpg > /dev/null 2>&1 &
	FFMPEGPID=$!
	for i in $(seq 1 4) ; do
		sleep 1m
		update_screenshot
	done
	timeout -k 12m 11m schroot --run-session -c $SESSION --preserve-environment -- torbrowser-launcher https://www.debian.org &
	for i in $(seq 1 4) ; do
		sleep 1m
		update_screenshot
	done
	schroot --end-session -c $SESSION
	kill $XPID $FFMPEGPID || true
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
first_test # test package from the archive
# then build package and test it (probably via triggering another job)
# not sure how to test updates. maybe just run old install?

cd
cleanup_all
trap - INT TERM EXIT
echo "$(date -u) - the end."

