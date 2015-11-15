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
	[ ! -f screenshot.png ] || mv screenshot.png $RESULTS/
	[ ! -f screenshot-thumb.png ] || mv screenshot-thumb.png $RESULTS/
	[ ! -f test-torbrowser-$SUITE.mpg ] || mv test-torbrowser-$SUITE.mpg $RESULTS/
	# shutdown and end session if it still exists
	schroot --run-session -c $SESSION --directory /tmp -u root -- service dbus stop || true
	schroot --end-session -c tbb-launcher-$SUITE-$(basename $TMPDIR) > /dev/null 2>&1 || true
	# delete main work dir
	cd
	rm $TMPDIR -r
	# end
	echo "$(date -u) - $TMPDIR deleted. Cleanup done."
}

update_screenshot() {
	TIMESTAMP=$(date +%Y%m%d%H%M)
	xwd -root -silent -display :$SCREEN.0 | xwdtopnm > screenshot.pnm 2>/dev/null
	pnmtopng screenshot.pnm > screenshot.png
	convert screenshot.png -adaptive-resize 128x96 screenshot-thumb.png
	# for publishing
	cp screenshot.png $RESULTS/screenshot_$TIMESTAMP.png
	# for the live screenshot plugin
	mv screenshot.png screenshot-thumb.png $WORKSPACE/
}

first_test() {
	echo
	local SESSION="tbb-launcher-$SUITE-$(basename $TMPDIR)"
	schroot --begin-session --session-name=$SESSION -c jenkins-torbrowser-launcher-$SUITE
	schroot --run-session -c $SESSION --directory /tmp -u root -- mkdir $HOME
	schroot --run-session -c $SESSION --directory /tmp -u root -- chown jenkins:jenkins $HOME
	schroot --run-session -c $SESSION --directory /tmp -u root -- service dbus start
	SCREEN=77
	Xvfb -ac -br -screen 0 1024x768x16 :$SCREEN &
	XPID=$!
	export DISPLAY=":$SCREEN.0"
	unset http_proxy
	unset https_proxy
	timeout -k 12m 11m schroot --run-session -c $SESSION --preserve-environment -- awesome &
	timeout -k 12m 11m schroot --run-session -c $SESSION --preserve-environment -- torbrowser-launcher https://www.debian.org &
	ffmpeg -f x11grab -i :$SCREEN.0 test-torbrowser-$SUITE.mpg > /dev/null 2>&1 &
	FFMPEGPID=$!
	for i in $(seq 1 16) ; do
		sleep 15
		update_screenshot
	done
	timeout -k 12m 11m schroot --run-session -c $SESSION --preserve-environment -- torbrowser-launcher https://www.debian.org &
	for i in $(seq 1 16) ; do
		sleep 15
		update_screenshot
	done
	schroot --run-session -c $SESSION --directory /tmp -u root -- service dbus stop
	schroot --end-session -c $SESSION
	kill $XPID $FFMPEGPID || true
	echo
}

#
# main
#

TMPDIR=$(mktemp -d)  # where everything actually happens
trap cleanup_all INT TERM EXIT
WORKSPACE=$(pwd)
mkdir -p results
RESULTS=$WORKSPACE/results
cd $TMPDIR

SUITE=$1
echo "$(date -u) - testing torbrowser-launcher on $SUITE now."
[ ! -f screenshot.png ] || rm screenshot.png
first_test # test package from the archive
# then build package and test it (probably via triggering another job)
# not sure how to test updates. maybe just run old install?

cd
cleanup_all
trap - INT TERM EXIT
echo "$(date -u) - the end."

