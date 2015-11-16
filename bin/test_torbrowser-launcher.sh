#!/bin/bash

# Copyright 2015 Holger Levsen <holger@layer-acht.org>
# released under the GPLv=2

DEBUG=false
. /srv/jenkins/bin/common-functions.sh
common_init "$@"

set -e

cleanup_all() {
	set +e
	if [ "$1" = "quiet" ] ; then
		echo "$(date -u) - everything ran nicely, congrats."
	fi
	# kill xvfb and ffmpeg
	kill $XPID $FFMPEGPID 2>/dev/null|| true
	# preserve screenshots
	[ ! -f screenshot.png ] || mv screenshot.png $RESULTS/
	[ ! -f screenshot-thumb.png ] || mv screenshot-thumb.png $RESULTS/
	[ ! -f $VIDEO ] || mv $VIDEO $RESULTS/
	[ ! -f screenshot_from_git.png ] || mv screenshot_from_git.png screenshot.png
	# shutdown and end session if it still exists
	STATUS=$(schroot -l --all-sessions | grep $SESSION || true)
	if [ -n "$STATUS" ] ; then
		echo "$(date -u ) - stopping dbus service."
		schroot --run-session -c $SESSION --directory /tmp -u root -- service dbus stop || true
		sleep 1
		schroot --end-session -c $SESSION || true
		echo "$(date -u ) - schroot session $SESSION end."
	fi
	# delete main work dir
	cd
	rm $TMPDIR -r
	# end
	echo "$(date -u) - $TMPDIR deleted. Cleanup done."
}

update_screenshot() {
	TIMESTAMP=$(date +%Y%m%d%H%M%S)
	ffmpeg -y -f x11grab -s $SIZE -i :$SCREEN.0 -frames 1 screenshot.png > /dev/null 2>&1
	convert screenshot.png -adaptive-resize 128x96 screenshot-thumb.png
	# for publishing
	cp screenshot.png $RESULTS/screenshot_$TIMESTAMP.png
	echo "screenshot_$TIMESTAMP.png preserved."
	# for the live screenshot plugin
	mv screenshot.png screenshot-thumb.png $WORKSPACE/
}

begin_session() {
	schroot --begin-session --session-name=$SESSION -c jenkins-torbrowser-launcher-$SUITE
	echo "Starting schroot session, schroot --run-session -c $SESSION -- now availble."
	schroot --run-session -c $SESSION --directory /tmp -u root -- mkdir $HOME
	schroot --run-session -c $SESSION --directory /tmp -u root -- chown jenkins:jenkins $HOME
}

end_session() {
	schroot --end-session -c $SESSION
	echo "$(date -u ) - schroot session $SESSION end."
	sleep 1
}

upgrade_to_experimental_version() {
	echo
	echo "$(date -u ) - upgrading to torbrowser-launcher from experimental…"
	echo "deb $MIRROR experimental main contrib" | schroot --run-session -c $SESSION --directory /tmp -u root -- tee -a /etc/apt/sources.list
	schroot --run-session -c $SESSION --directory /tmp -u root -- apt-get update
	schroot --run-session -c $SESSION --directory /tmp -u root -- apt-get -y install -t experimental torbrowser-launcher
}

build_and_upgrade_to_git_version() {
	echo
	echo "$(date -u ) - building torbrowser-launcher from git, branch $BRANCH…"
	schroot --run-session -c $SESSION --directory $TMPDIR/git -- debuild -b -uc -us
	DEB=$(cd $TMPDIR ; ls torbrowser-launcher_*deb)
	CHANGES=$(cd $TMPDIR ; ls torbrowser-launcher_*changes)
	echo "$(date -u ) - installing $DEB…"
	schroot --run-session -c $SESSION --directory $TMPDIR -u root -- dpkg -i $DEB
	rm $TMPDIR/git -r
	cat $TMPDIR/$CHANGES
	schroot --run-session -c $SESSION --directory $TMPDIR -- dcmd rm $CHANGES
}

download_and_launch() {
	echo
	echo "$(date -u) - Test download_and_launch begins."
	echo "$(date -u ) - starting dbus service."
	schroot --run-session -c $SESSION --directory /tmp -u root -- service dbus start
	sleep 2
	echo "$(date -u) - starting Xfvb on :$SCREEN.0…"
	Xvfb -ac -br -screen 0 ${SIZE}x24 :$SCREEN &
	XPID=$!
	sleep 1
	export DISPLAY=":$SCREEN.0"
	echo export DISPLAY=":$SCREEN.0"
	unset http_proxy
	unset https_proxy
	echo "$(date -u) - starting awesome…"
	timeout -k 30m 29m schroot --run-session -c $SESSION --preserve-environment -- awesome &
	sleep 2
	DBUS_SESSION_FILE=$(mktemp)
	DBUS_SESSION_POINTER=$(schroot --run-session -c $SESSION --preserve-environment -- ls $HOME/.dbus/session-bus/ -t1 | head -1)
	schroot --run-session -c $SESSION --preserve-environment -- cat $HOME/.dbus/session-bus/$DBUS_SESSION_POINTER > $DBUS_SESSION_FILE
	. $DBUS_SESSION_FILE && export DBUS_SESSION_BUS_ADDRESS
	echo export DBUS_SESSION_BUS_ADDRESS=$DBUS_SESSION_BUS_ADDRESS
	rm $DBUS_SESSION_FILE
	ffmpeg -f x11grab -s $SIZE -i :$SCREEN.0 $VIDEO > /dev/null 2>&1 &
	FFMPEGPID=$!
	echo "'$(date -u) - starting torbrowser tests'" | tee >( xargs schroot --run-session -c $SESSION --preserve-environment -- notify-send )
	update_screenshot
	echo "$(date -u) - starting torbrowser-launcher the first time…"
	( timeout -k 30m 29m schroot --run-session -c $SESSION --preserve-environment -- torbrowser-launcher --settings || true ) &
	sleep 10
	update_screenshot
	echo "$(date -u) - pressing, <tab>, <return>…"
	xvkbd -text "\t" > /dev/null 2>&1
	sleep 1
	update_screenshot
	xvkbd -text "\r" > /dev/null 2>&1
	for i in $(seq 1 20) ; do
		sleep 30
		update_screenshot
		# this directory only exist once torbrower has been successfully installed

		STATUS="$(schroot --run-session -c $SESSION -- test -d $HOME/.local/share/torbrowser/tbb/x86_64/tor-browser_en-US/Browser || echo $(date -u ) - torbrowser downloaded and installed. )"
		if [ -n "$STATUS" ] ; then
			sleep 10
			echo "'$STATUS'" | tee >( xargs schroot --run-session -c $SESSION --preserve-environment -- notify-send )
			update_screenshot
			break
		fi
	done
	if [ ! -n "$STATUS" ] ; then
		echo "'$(date -u) - could not download torbrowser, please investigate.'" | tee >( xargs schroot --run-session -c $SESSION --preserve-environment -- notify-send -u critical )
		update_screenshot
		exit 1
	fi
	echo "$(date -u) - waiting for torbrowser to start…"
	for i in $(seq 1 6) ; do
		sleep 10
		# this directory only exist once torbrower has successfully started
		STATUS="$(schroot --run-session -c $SESSION -- test -d $HOME/.local/share/torbrowser/tbb/x86_64/tor-browser_en-US/Browser/TorBrowser/Data/Browser/profile.default || echo $(date -u ) - torbrowser running. )"
		if [ -n "$STATUS" ] ; then
			sleep 10
			echo "'$STATUS'" | tee >( xargs schroot --run-session -c $SESSION --preserve-environment -- notify-send )
			update_screenshot
			break
		fi
	done
	if [ ! -n "$STATUS" ] ; then
		echo "'$(date -u) - could not start torbrowser, please investigate.'" | tee >( xargs schroot --run-session -c $SESSION --preserve-environment -- notify-send -u critical )
		update_screenshot
		exit 1
	fi
	echo "$(date -u) - pressing <return>, to connect directly via tor…"
	xvkbd -text "\r" > /dev/null 2>&1
	sleep 5
	for i in $(seq 1 2) ; do
		sleep 15
		update_screenshot
	done
	echo "$(date -u) - pressing <ctrl>-l - about to enter an URL…"
	xvkbd -text "\Cl" > /dev/null 2>&1
	sleep 3
	URL="https://www.debian.org"
	xvkbd -text "$URL" > /dev/null 2>&1
	update_screenshot
	sleep 0.5
	xvkbd -text "\r" > /dev/null 2>&1
	update_screenshot
	for i in $(seq 1 2) ; do
		sleep 15
		update_screenshot
	done
	sleep 1
	echo "'$(date -u) - torbrowser tests end.'" | tee >( xargs schroot --run-session -c $SESSION --preserve-environment -- notify-send )
	update_screenshot
	echo "$(date) - telling awesome to quit."
	echo 'awesome.quit()' | schroot --run-session -c $SESSION --preserve-environment -- awesome-client
	sleep 1
	schroot --run-session -c $SESSION --directory /tmp -u root -- service dbus stop
	sleep 1
	echo "$(date -u ) - killing Xfvb and ffmpeg."
	kill $XPID $FFMPEGPID || true
	sleep 1
	echo "$(date -u ) - Test ends."
	echo
}

#
# prepare
#
if [ -z "$1" ] ; then
	echo "call $0 with a suite as param."
	exit 1
fi
SUITE=$1
TMPDIR=$(mktemp -d)  # where everything actually happens
SESSION="tbb-launcher-$SUITE-$(basename $TMPDIR)"
STARTTIME=$(date +%Y%m%d%H%M)
VIDEO=test-torbrowser-${SUITE}_$STARTTIME.mpg
SIZE=1024x768
SCREEN=$EXECUTOR_NUMBER
if [ "$2" = "git" ] ; then
	if [ -z "$3"  ] ; then
		BRANCH=master
	else
		BRANCH=$3
	fi
	echo "$(date -u) - preserving git workspace."
	git branch -av
	mkdir $TMPDIR/git
	cp -r * $TMPDIR/git
elif [ "$SUITE" = "experimental" ] || [ "$2" = "experimental" ] ; then
	SUITE=unstable
	EXPERIMENTAL=yes
fi
WORKSPACE=$(pwd)
RESULTS=$WORKSPACE/results
[ ! -f screenshot.png ] || mv screenshot.png screenshot_from_git.png
mkdir -p $RESULTS
cd $TMPDIR
trap cleanup_all INT TERM EXIT

#
# main
#
echo "$(date -u) - testing torbrowser-launcher on $SUITE now."
begin_session
if [ "$2" = "git" ] ; then
	build_and_upgrade_to_git_version
elif [ "$EXPERIMENTAL" = "yes" ] ; then
	upgrade_to_experimental_version
fi
download_and_launch
end_session

# the end
trap - INT TERM EXIT
cleanup_all quiet
echo "$(date -u) - the end."

