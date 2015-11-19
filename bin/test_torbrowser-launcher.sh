#!/bin/bash

# Copyright 2015 Holger Levsen <holger@layer-acht.org>
# released under the GPLv=2

DEBUG=false
. /srv/jenkins/bin/common-functions.sh
common_init "$@"

set -e

# dependencies used in the schroot are described in job-cfg/torbrowser-launcher.yaml, see how schroot-create.sh is called there.
# additionally this script needs the following packages: xvfb, xvkbd, ffmpeg, gocr, imagemagick

cleanup_all() {
	set +e
	# $1 is empty when called via trap
	if [ "$1" = "quiet" ] ; then
		echo "$(date -u) - everything ran nicely, congrats."
	fi
	# kill xvfb and ffmpeg
	kill $XPID $FFMPEGPID 2>/dev/null|| true
	# preserve screenshots and video
	cd $TMPDIR
	[ ! -f $VIDEO ] || mv $VIDEO $RESULTS/
	cd $WORKSPACE
	[ ! -f screenshot.png ] || rm screenshot.png
	[ ! -f screenshot-thumb.png ] || rm screenshot-thumb.png
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
	rm $TMPDIR $TBL_LOGFILE -rf
	# end
	echo "$(date -u) - $TMPDIR deleted. Cleanup done."
}

cleanup_duplicate_screenshots() {
	cd $RESULTS
	echo "$(date -u) - removing duplicate and similar creenshots."
	# loop backwards through the screenshots and remove similar ones
	# this results in keeping the interesting ones :)
	MAXDIFF=2500 # pixels
	for i in $(ls -r1 *.png | xargs echo) ; do
		for j in $(ls -r1 *.png | xargs echo) ; do
			if [ "$j" = "$i" ] ; then
				break
			elif [ ! -f $j ] || [ ! -f $i ] ; then
				break
			fi
			# here we check the difference in pixels between the two images
			PIXELS=$(compare -metric AE $i $j /dev/null 2>&1 || true)
			# if it's an integer…
			if [[ "$PIXELS" =~ ^[0-9]+$ ]] && [ $PIXELS -le $MAXDIFF ] ; then
				echo "$(date -u ) - removing $j, $PIXELS pixels difference."
				rm $j
			fi
		done
	done
	cp $(ls -r1 *.png | head -1) final_state.png
	convert final_state.png -adaptive-resize 128x96 final_state-thumb.png
}

update_screenshot() {
	TIMESTAMP=$(date +%Y%m%d%H%M%S)
	# probably there is something more lightweight to grab a screenshot from xvfb…
	ffmpeg -y -f x11grab -s $SIZE -i :$SCREEN.0 -frames 1 screenshot.png > /dev/null 2>&1
	convert screenshot.png -adaptive-resize 128x96 screenshot-thumb.png
	# for later publishing
	cp screenshot.png $RESULTS/screenshot_$TIMESTAMP.png
	# for the live screenshot plugin
	mv screenshot.png screenshot-thumb.png $WORKSPACE/
	echo "screenshot_$TIMESTAMP.png taken."
}

begin_session() {
	# create schroot session
	schroot --begin-session --session-name=$SESSION -c jenkins-torbrowser-launcher-$SUITE
	echo "Starting schroot session, schroot --run-session -c $SESSION -- now availble."
	schroot --run-session -c $SESSION --directory /tmp -u root -- mkdir $HOME
	schroot --run-session -c $SESSION --directory /tmp -u root -- chown jenkins:jenkins $HOME
}

end_session() {
	# destroy schroot session
	schroot --end-session -c $SESSION
	echo "$(date -u ) - schroot session $SESSION end."
	sleep 1
}

upgrade_to_newer_packaged_version_in() {
	local SUITE=$1
	echo
	echo "$(date -u ) - upgrading to torbrowser-launcher from $SUITE"
	echo "deb $MIRROR $SUITE main contrib" | schroot --run-session -c $SESSION --directory /tmp -u root -- tee -a /etc/apt/sources.list
	schroot --run-session -c $SESSION --directory /tmp -u root -- apt-get update
	schroot --run-session -c $SESSION --directory /tmp -u root -- apt-get -y install -t $SUITE torbrowser-launcher
}

upgrade_to_package_build_from_git() {
	echo
	local BRANCH=$1
	# GIT_URL is set by jenkins
	echo "$(date -u ) - building Debian package based on branch $BRANCH from $GIT_URL."
	# build package
	schroot --run-session -c $SESSION --directory $TMPDIR/git -- debuild -b -uc -us
	# install it
	local DEB=$(cd $TMPDIR ; ls torbrowser-launcher_*deb)
	local CHANGES=$(cd $TMPDIR ; ls torbrowser-launcher_*changes)
	echo "$(date -u ) - $DEB will be installed."
	schroot --run-session -c $SESSION --directory $TMPDIR -u root -- dpkg -i $DEB
	# cleanup
	rm $TMPDIR/git -r
	cat $TMPDIR/$CHANGES
	schroot --run-session -c $SESSION --directory $TMPDIR -- dcmd rm $CHANGES
}

download_and_launch() {
	echo
	echo "$(date -u) - Test download_and_launch begins."
	echo "$(date -u ) - starting dbus service."
	# yes, torbrowser needs dbus
	schroot --run-session -c $SESSION --directory /tmp -u root -- service dbus start
	sleep 2
	echo "$(date -u) - starting Xfvb on :$SCREEN.0 now."
	# start X on virtual framebuffer device
	Xvfb -ac -br -screen 0 ${SIZE}x24 :$SCREEN &
	XPID=$!
	sleep 1
	# configure environment
	export DISPLAY=":$SCREEN.0"
	echo export DISPLAY=":$SCREEN.0"
	unset http_proxy
	unset https_proxy
	#export LANGUAGE="de"
	#export LANG="de_DE.UTF-8"
	#export LC_ALL="de_DE.UTF-8"
	echo "$(date -u) - starting awesome."
	timeout -k 30m 29m schroot --run-session -c $SESSION --preserve-environment -- awesome &
	sleep 2
	# configure dbus session for this user's session
	DBUS_SESSION_FILE=$(mktemp -t torbrowser-launcher-XXXXXX)
	DBUS_SESSION_POINTER=$(schroot --run-session -c $SESSION --preserve-environment -- ls $HOME/.dbus/session-bus/ -t1 | head -1)
	schroot --run-session -c $SESSION --preserve-environment -- cat $HOME/.dbus/session-bus/$DBUS_SESSION_POINTER > $DBUS_SESSION_FILE
	. $DBUS_SESSION_FILE && export DBUS_SESSION_BUS_ADDRESS
	echo export DBUS_SESSION_BUS_ADDRESS=$DBUS_SESSION_BUS_ADDRESS
	rm $DBUS_SESSION_FILE
	# start ffmpeg to capture a video of the interesting bits of the test
	ffmpeg -f x11grab -s $SIZE -i :$SCREEN.0 $VIDEO > /dev/null 2>&1 &
	FFMPEGPID=$!
	echo "'$(date -u) - starting torbrowser tests'" | tee | xargs schroot --run-session -c $SESSION --preserve-environment -- notify-send
	update_screenshot
	echo "$(date -u) - starting torbrowser-launcher, opening settings dialog."
	# set PYTHONUNBUFFERED to get unbuffered output from python, so we can grep in it in real time
	export PYTHONUNBUFFERED=true
	( timeout -k 30m 29m schroot --run-session -c $SESSION --preserve-environment -- /usr/bin/torbrowser-launcher --settings 2>&1 |& tee $TBL_LOGFILE || true ) &
	sleep 10
	update_screenshot
	echo "$(date -u) - pressing <tab>"
	xvkbd -text "\t" > /dev/null 2>&1
	sleep 1
	TBL_VERSION=$(schroot --run-session -c $SESSION -- dpkg --status torbrowser-launcher |grep ^Version|cut -d " " -f2)
	if dpkg --compare-versions $TBL_VERSION lt 0.2.0-1~ ; then
		echo "$(date -u) - torbrowser-launcher version <0.2.0-1~ detected ($TBL_VERSION), pressing <tab> three times more."
		xvkbd -text "\t\t\t" > /dev/null 2>&1
		sleep 1
	elif dpkg --compare-versions $TBL_VERSION lt 0.2.2-1~ ; then
		echo "$(date -u) - torbrowser-launcher version <0.2.2-1~ detected ($TBL_VERSION), pressing <tab> twice more."
		xvkbd -text "\t\t" > /dev/null 2>&1
		sleep 1
	fi
	update_screenshot
	echo "$(date -u) - pressing <return>"
	xvkbd -text "\r" > /dev/null 2>&1
	sleep 5
	update_screenshot
	SETTINGS_DONE=$(pgrep -f "$SESSION --preserve-environment -- torbrowser-launcher --settings" || true)
	if [ -n "$SETTINGS_DONE" ] ; then
		echo "'$(date -u) - settings dialog still there, aborting.'" | tee | xargs schroot --run-session -c $SESSION --preserve-environment -- notify-send -u critical
		update_screenshot
		cleanup_duplicate_screenshots
		exit 1
	fi
	# allow the download to take up to ~15 minutes (891 seconds)
	# ( echo -n "0" ; for i in $(seq 1 33) ; do echo -n "+$i+10" ; done ; echo ) | bc
	# we watch the download directory and parse torbrowser-launchers stdout, so usually this loop won't run this long
	for i in $(seq 1 33) ; do
		sleep 10 ; sleep $i
		STATUS="$(grep '^Download error:' $TBL_LOGFILE || true)"
		if [ -n "$STATUS" ] ; then
			echo "'$(date -u) - $STATUS'" | tee | xargs schroot --run-session -c $SESSION --preserve-environment -- notify-send -u critical
			update_screenshot
			cleanup_duplicate_screenshots
			exit 1
		fi
		# download is finished once BROWSER_DIR_EN or BROWSER_DIR_DE exist
		# as these directories only exist once torbrower has been successfully installed
		# (and pattern matching doesnt work because of schroot…)
		local BROWSER_DIR_EN=$HOME/.local/share/torbrowser/tbb/x86_64/tor-browser_en-US/Browser
		local BROWSER_DIR_DE=$HOME/.local/share/torbrowser/tbb/x86_64/tor-browser_de/Browser
		STATUS="$(schroot --run-session -c $SESSION -- test ! -d $BROWSER_DIR_EN -a ! -d $BROWSER_DIR_DE || echo $(date -u ) - torbrowser downloaded and installed, configuring tor now. )"
		if [ -n "$STATUS" ] ; then
			update_screenshot
			break
		fi
		update_screenshot
	done
	if [ ! -n "$STATUS" ] ; then
		echo "'$(date -u) - could not download torbrowser, please investigate.'" | tee | xargs schroot --run-session -c $SESSION --preserve-environment -- notify-send -u critical
		update_screenshot
		cleanup_duplicate_screenshots
		exit 1
	fi
	echo "$(date -u) - waiting for torbrowser to start the tor network settings dialogue."
	# allow up to 63 seconds for torbrowser to start the tor network settings dialogue
	for i in $(seq 1 7) ; do
		sleep 5 ; sleep $i
		# this directory only exists once torbrower has successfully started
		# (and pattern matching doesnt work because of schroot…)
		local BROWSER_PROFILE=TorBrowser/Data/Browser/profile.default
		STATUS="$(schroot --run-session -c $SESSION -- test ! -d $BROWSER_DIR_EN/$BROWSER_PROFILE -a ! -d $BROWSER_DIR_DE/$BROWSER_PROFILE || echo $(date -u ) - torbrowser running. )"
		if [ -n "$STATUS" ] ; then
			sleep 10
			break
		fi
	done
	if [ ! -n "$STATUS" ] ; then
		echo "'$(date -u) - could not start torbrowser, please investigate.'" | tee | xargs schroot --run-session -c $SESSION --preserve-environment -- notify-send -u critical
		update_screenshot
		cleanup_duplicate_screenshots
		exit 1
	fi
	echo "$(date -u) - pressing <return>, to connect directly via tor."
	xvkbd -text "\r" > /dev/null 2>&1
	sleep 3
	update_screenshot
	# allow up to 63 seconds for torbrowser to make the first connection through tor
	for i in $(seq 1 7) ; do
		sleep 5 ; sleep $i
		update_screenshot
		TOR_RUNNING=$(gocr $WORKSPACE/screenshot.png 2>/dev/null | egrep "(Search securely|Tor Is NOT all you need to browse|There are many ways you can help)" || true)
		if [ -n "$TOR_RUNNING" ] ; then
			echo "$(date -u) - torbrowser is working as it should, good."
			break
		fi
	done
	if [ -z "$TOR_RUNNING" ] ; then
		echo "'$(date -u) - could not connect successfuly via tor or could not run torbrowser at all. Aborting.'" | tee | xargs schroot --run-session -c $SESSION --preserve-environment -- notify-send -u critical
		update_screenshot
		cleanup_duplicate_screenshots
		cleanup_all
		exec /srv/jenkins/bin/abort.sh
		exit 0
	fi
	BONUS_LEVEL_1=""
	URL="http://vwakviie2ienjx6t.onion/debian/" 	# see http://richardhartmann.de/blog/posts/2015/08/24-Tor-enabled_Debian_mirror/
	echo "$(date -u) - pressing <ctrl>-l - about to enter $URL as URL."
	xvkbd -text "\Cl" > /dev/null 2>&1
	sleep 3
	xvkbd -text "$URL" > /dev/null 2>&1
	sleep 1
	xvkbd -text "\r" > /dev/null 2>&1
	sleep 2
	# allow up up to 30 seconds to load the url
	for i in $(seq 1 4) ; do
		sleep 5 ; sleep $i
		URL_LOADED=$(gocr $WORKSPACE/screenshot.png 2>/dev/null | grep -c -i "README" || true)
		update_screenshot
		if [ $URL_LOADED -ge 4 ] ; then
			echo "$(date -u) - $URL loaded fine, very much an archive in there, great."
			BONUS_LEVEL_1="yes"
			break
		fi
	done
	BONUS_LEVEL_2=""
	URL="https://www.debian.org"
	echo "$(date -u) - pressing <ctrl>-l - about to enter $URL as URL."
	xvkbd -text "\Cl" > /dev/null 2>&1
	sleep 3
	xvkbd -text "$URL" > /dev/null 2>&1
	sleep 1
	xvkbd -text "\r" > /dev/null 2>&1
	sleep 2
	# allow up up to 30 seconds to load the url
	for i in $(seq 1 4) ; do
		sleep 5 ; sleep $i
		URL_LOADED=$(gocr $WORKSPACE/screenshot.png 2>/dev/null | grep -c "Debian" || true)
		update_screenshot
		if [ $URL_LOADED -ge 6 ] ; then
			echo "$(date -u) - $URL loaded fine, very much Debian in there, great."
			BONUS_LEVEL_2="yes"
			break
		fi
	done
	if [ -n "$BONUS_LEVEL_1" ] && [ -n "$BONUS_LEVEL_2" ] ; then
		BONUS_MSG="Very well done."
		BONUS_COLORS="-bg green -fg black"
	elif [ -n "$BONUS_LEVEL_1" ] || [ -n "$BONUS_LEVEL_2" ] ; then
		BONUS_MSG="Well done."
		BONUS_COLORS="-bg lightgreen -fg black"
	else
		BONUS_MSG=""
		BONUS_COLORS=""
	fi
	schroot --run-session -c $SESSION --preserve-environment -- xterm $BONUS_COLORS -fs 64 -hold -T '$(date +'%a %d %b')' -e "figlet -c -f banner '$(date +'%a %d %b')'" 2>/dev/null || true &
	if [ -n "$BONUS_MSG" ] ; then
		schroot --run-session -c $SESSION --preserve-environment -- xterm $BONUS_COLORS -fs 48 -hold -T "$BONUS_MSG" -e "figlet -c -f banner '$BONUS_MSG'" 2>/dev/null || true &
	fi
	sleep 1
	echo "'$(date -u) - torbrowser tests end. $BONUS_MSG'" | tee | xargs schroot --run-session -c $SESSION --preserve-environment -- notify-send
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

merge_debian_branch() {
	local DEBIAN_GIT_URL="git://git.debian.org/git/collab-maint/torbrowser-launcher.git"
	local DEBIAN_BRANCH="debian/$1"
	echo "$(date -u) - Merging branch $DEBIAN_BRANCH into $COMMIT_HASH now."
	echo
	git log -1
	git checkout -b $BRANCH
	git remote add debian $DEBIAN_GIT_URL
	git fetch --no-tags debian
	git merge --no-stat --no-edit $DEBIAN_BRANCH
	local BUILD_VERSION="$(dpkg-parsechangelog |grep ^Version:|cut -d " " -f2).0~jenkins-test-$COMMIT_HASH"
	local COMMIT_MSG1="Automatically build by jenkins using the branch $DEBIAN_BRANCH (from $DEBIAN_GIT_URL) merged into $COMMIT_HASH."
	# GIT_URL AND GIT_BRANCH are set by jenkins
	local COMMIT_MSG2="$COMMIT_HASH is from branch $(echo $GIT_BRANCH|cut -d '/' -f2) from $GIT_URL."
	dch -R $COMMIT_MSG1
	dch -v $BUILD_VERSION $COMMIT_MSG2
}

prepare_git_workspace_copy() {
	echo "$(date -u) - preparing git workspace copy in $TMPDIR/git"
	git branch -av
	mkdir $TMPDIR/git
	cp -r * $TMPDIR/git
	echo
}

revert_git_merge() {
	git reset --hard
	git checkout -f -q $COMMIT_HASH
	git branch -D $BRANCH
}

#
# prepare
#
if [ -z "$1" ] ; then
	echo "call $0 with a suite as param."
	exit 1
fi
SUITE=$1
UPGRADE_SUITE=""
TMPDIR=$(mktemp -d -t torbrowser-launcher-XXXXXX)
TBL_LOGFILE=$(mktemp -t torbrowser-launcher-XXXXXX)
SESSION="tbb-launcher-$SUITE-$(basename $TMPDIR)"
STARTTIME=$(date +%Y%m%d%H%M)
VIDEO=test-torbrowser-${SUITE}_$STARTTIME.mpg
SIZE=1024x768
SCREEN=$EXECUTOR_NUMBER
if [ "$2" = "git" ] ; then
	if [ "$3" = "merge"  ] ; then
		# merge debian branch into upstream master branch
		BRANCH=upstream-master-plus-debian-packaging
		COMMIT_HASH=$(git log -1 --oneline|cut -d " " -f1)
		merge_debian_branch $4
		prepare_git_workspace_copy
		revert_git_merge
	else
		# just use this branch
		BRANCH=$3
		prepare_git_workspace_copy
	fi
elif [ "$SUITE" = "experimental" ] || [ "$2" = "experimental" ] ; then
	SUITE=unstable
	UPGRADE_SUITE=experimental
elif [ "$2" = "backports" ] ; then
	UPGRADE_SUITE=$SUITE-backports
elif [ "$2" = "unstable" ] ; then
	UPGRADE_SUITE=unstable
fi
WORKSPACE=$(pwd)
RESULTS=$WORKSPACE/results
rm -f $RESULTS/*.png $RESULTS/*.mpg
[ ! -f screenshot.png ] || mv screenshot.png screenshot_from_git.png
mkdir -p $RESULTS
cd $TMPDIR
# use trap to always clean up
trap cleanup_all INT TERM EXIT

#
# main
#
echo "$(date -u) - testing torbrowser-launcher on $SUITE now."
begin_session
# the default is to test the packaged version from $SUITE
# and there are two variations:
if [ "$2" = "git" ] ; then
	upgrade_to_package_build_from_git $BRANCH
elif [ -n "$UPGRADE_SUITE" ] ; then
	upgrade_to_newer_packaged_version_in $UPGRADE_SUITE
fi
download_and_launch
end_session
cleanup_duplicate_screenshots

# the end
trap - INT TERM EXIT
cleanup_all quiet
echo "$(date -u) - the end."

