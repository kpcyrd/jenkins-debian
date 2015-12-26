#!/bin/bash

# Copyright 2014-2015 Holger Levsen <holger@layer-acht.org>
# released under the GPLv=2

DEBUG=true
. /srv/jenkins/bin/common-functions.sh
common_init "$@"

# common code defining db access
. /srv/jenkins/bin/reproducible_common.sh

cleanup_tmpdirs() {
	set +e
	cd
	$RSSH "sudo chflags -R noschg $TMPDIR"
	$RSSH "rm -r $TMPDIR" || true
	rm $TMPDIR -r
	$RSSH 'sudo rm -rf /usr/src'
}

create_results_dirs() {
	mkdir -p $BASE/freebsd/dbd
}

save_freebsd_results() {
	local RUN=$1
	echo "============================================================================="
	echo "$(date -u) - Saving FreeBSD (branch $FREEBSD_TARGET at ${FREEBSD_VERSION[$FREEBSD_TARGET]}) build results for $RUN run."
	echo "============================================================================="
	mkdir -p $TMPDIR/$RUN/
	# copy results over
	DUMMY_DATE="$(date -u +'%Y-%m-%d')T00:00:00Z"
	$RSSH "sudo find $TMPDIR -newer $TMPDIR -exec touch -d '$DUMMY_DATE' {} \;"
	$RSSH "sudo find $TMPDIR -print0 | LC_ALL=C sort -z | sudo tar --null -T - --no-recursion -cJf $TMPDIR.tar.xz"
	$RSCP:$TMPDIR.tar.xz $TMPDIR/$RUN/$TARGET_NAME.tar.xz
	$RSSH "sudo chflags -R noschg $TMPDIR ; sudo rm -r $TMPDIR $TMPDIR.tar.xz ; mkdir $TMPDIR"
}

run_diffoscope_on_results() {
	TIMEOUT="30m"
	DIFFOSCOPE="$(schroot --directory /tmp -c source:jenkins-reproducible-${DBDSUITE}-diffoscope diffoscope -- --version 2>&1)"
	echo "============================================================================="
	echo "$(date -u) - Running $DIFFOSCOPE on FreeBSD (branch $FREEBSD_TARGET at ${FREEBSD_VERSION}) build results."
	echo "============================================================================="
	mkdir -p $TMPDIR
	FILES_HTML[$FREEBSD_TARGET]=$(mktemp --tmpdir=$TMPDIR)
	#echo "       <ul>" > ${FILES_HTML[$FREEBSD_TARGET]}
	GOOD_FILES[$FREEBSD_TARGET]=0
	ALL_FILES[$FREEBSD_TARGET]=0
	SIZE=""
	create_results_dirs
	echo "       <table><tr><th>Artifacts for <code>$TARGET_NAME</code></th></tr>" >> ${FILES_HTML[$FREEBSD_TARGET]}
	if [ ! -d $TMPDIR/b1 ] || [ ! -d $TMPDIR/b1 ] ; then
		echo "Warning, one of the two builds failed, not running diffoscope…"
		echo "<tr><td>$TARGET_NAME failed to build from source.</td></tr>" >> ${FILES_HTML[$FREEBSD_TARGET]}
		echo "</table>" >> ${FILES_HTML[$FREEBSD_TARGET]}
		GOOD_PERCENT[$FREEBSD_TARGET]="0"
		return # FIXME: further refactoring needed
	fi
	cd $TMPDIR/b1
	tree .
	for j in $(find * -type f |sort -u ) ; do
		ALL_FILES[$FREEBSD_TARGET]=$(( ${ALL_FILES[$FREEBSD_TARGET]}+1 ))
		call_diffoscope . $j
		get_filesize $j
		if [ -f $TMPDIR/$j.html ] ; then
			mkdir -p $BASE/freebsd/dbd/$(dirname $j)
			mv $TMPDIR/$j.html $BASE/freebsd/dbd/$j.html
			echo "         <tr><td><a href=\"dbd/$j.html\"><img src=\"/userContent/static/weather-showers-scattered.png\" alt=\"unreproducible icon\" /> $j</a> ($SIZE) is unreproducible.</td></tr>" >> ${FILES_HTML[$FREEBSD_TARGET]}
		else
			SHASUM=$(sha256sum $j|cut -d " " -f1)
			echo "         <tr><td><img src=\"/userContent/static/weather-clear.png\" alt=\"reproducible icon\" /> $j ($SHASUM, $SIZE) is reproducible.</td></tr>" >> ${FILES_HTML[$FREEBSD_TARGET]}
			GOOD_FILES[$FREEBSD_TARGET]=$(( ${GOOD_FILES[$FREEBSD_TARGET]}+1 ))
			rm -f $BASE/freebsd/dbd/$j.html # cleanup from previous (unreproducible) tests - if needed
		fi
	done
	echo "       </table>" >> ${FILES_HTML[$FREEBSD_TARGET]}
	GOOD_PERCENT[$FREEBSD_TARGET]=$(echo "scale=1 ; (${GOOD_FILES[$FREEBSD_TARGET]}*100/${ALL_FILES[$FREEBSD_TARGET]})" | bc)
}

#
# main
#
FREEBSD_TARGETS="master stable/10 release/10.2.0"
# arrays to save results
declare -A ALL_FILES
declare -A GOOD_FILES
declare -A GOOD_PERCENT
declare -A FREEBSD
declare -A FREEBSD_VERSION
declare -A FILES_HTML
for FREEBSD_TARGET in ${FREEBSD_TARGETS} ;do
	set -e
	RSSH="ssh -o Batchmode=yes freebsd-jenkins.debian.net"
	RSCP="scp -r freebsd-jenkins.debian.net"
	TMPBUILDDIR=/usr/src
	$RSSH 'sudo rm -rf /usr/src ; sudo mkdir /usr/src ; sudo chown jenkins /usr/src'  ### this is tmpfs on linux, we should move this to tmpfs on FreeBSD too
	TMPDIR=$($RSSH 'TMPDIR=/srv/reproducible-results mktemp -d -t rbuild-freebsd-XXXXXXXX')  # used to compare results
	DATE=$(date -u +'%Y-%m-%d')
	START=$(date +'%s')
	trap cleanup_tmpdirs INT TERM EXIT
	echo "============================================================================="
	echo "$(date -u) - FreeBSD host info"
	echo "============================================================================="
	$RSSH freebsd-version

	echo "============================================================================="
	echo "$(date -u) - Cloning FreeBSD git repository."
	echo "============================================================================="
	$RSSH git clone --depth 1 --branch $FREEBSD_TARGET https://github.com/freebsd/freebsd.git $TMPBUILDDIR
	FREEBSD[$FREEBSD_TARGET]=$($RSSH "cd $TMPBUILDDIR ; git log -1")
	FREEBSD_VERSION[$FREEBSD_TARGET]=$($RSSH "cd $TMPBUILDDIR ; git describe --always")
	echo "This is FreeBSD branch $FREEBSD_TARGET at ${FREEBSD_VERSION[$FREEBSD_TARGET]}."
	echo
	$RSSH "cd $TMPBUILDDIR ; git log -1"
	TARGET_NAME=$(echo "freebsd_${FREEBSD_TARGET}_git${FREEBSD_VERSION[$FREEBSD_TARGET]}" | sed "s#/#-#g")

	echo "============================================================================="
	echo "$(date -u) - Building FreeBSD (branch $FREEBSD_TARGET at ${FREEBSD_VERSION[$FREEBSD_TARGET]}) - first build run."
	echo "============================================================================="
	export TZ="/usr/share/zoneinfo/Etc/GMT+12"
	export LANG="en_GB.UTF-8"
	NUM_CPU=4 # if someone could tell me how to determine this on FreeBSD, this would be neat
	# actually build everything
	if ( $RSSH "cd $TMPBUILDDIR ; TZ=$TZ LANG=$LANG sudo make -j $NUM_CPU buildworld" && \
	  $RSSH "cd $TMPBUILDDIR ; TZ=$TZ LANG=$LANG sudo make -j $NUM_CPU buildkernel" && \
	  $RSSH "cd $TMPBUILDDIR ; TZ=$TZ LANG=$LANG DESTDIR=$TMPDIR sudo make -j $NUM_CPU installworld" && \
	  $RSSH "cd $TMPBUILDDIR ; TZ=$TZ LANG=$LANG DESTDIR=$TMPDIR sudo make -j $NUM_CPU installkernel" && \
	  $RSSH "cd $TMPBUILDDIR ; TZ=$TZ LANG=$LANG DESTDIR=$TMPDIR sudo make -j $NUM_CPU distribution" ) ; then
		# save results in b1
		save_freebsd_results b1
	else
		cleanup_tmpdirs
		echo "$(date -u ) - failed to build FreeBSD (branch $FREEBSD_TARGET at ${FREEBSD_VERSION[$FREEBSD_TARGET]}) in the first run, stopping."
		run_diffoscope_on_results
		continue
	fi

	# set time forward 398 days and some
	$RSSH "sudo service ntpd stop ; sudo date --set='+398 days +6 hours +23 minutes' ; date"
	echo "$(date -u) - system is running in the future now."

	echo "============================================================================="
	echo "$(date -u) - Building FreeBSD (branch $FREEBSD_TARGET at ${FREEBSD_VERSION[$FREEBSD_TARGET]}) - second build run."
	echo "============================================================================="
	export TZ="/usr/share/zoneinfo/Etc/GMT-14"
	export LANG="fr_CH.UTF-8"
	export LC_ALL="fr_CH.UTF-8"
	###export PATH="$PATH:/i/capture/the/path"
	###umask 0002
	# use allmost all cores for second build
	NEW_NUM_CPU=$(echo $NUM_CPU-1|bc)
	# actually build everything
	if ( $RSSH "cd $TMPBUILDDIR ; TZ=$TZ LANG=$LANG LC_ALL=$LC_ALL sudo make -j $NEW_NUM_CPU buildworld" && \
	  $RSSH "cd $TMPBUILDDIR ; TZ=$TZ LANG=$LANG LC_ALL=$LC_ALL sudo make -j $NEW_NUM_CPU buildkernel" && \
	  $RSSH "cd $TMPBUILDDIR ; TZ=$TZ LANG=$LANG LC_ALL=$LC_ALL DESTDIR=$TMPDIR sudo make -j $NEW_NUM_CPU installworld" && \
	  $RSSH "cd $TMPBUILDDIR ; TZ=$TZ LANG=$LANG LC_ALL=$LC_ALL DESTDIR=$TMPDIR sudo make -j $NEW_NUM_CPU installkernel" && \
	  $RSSH "cd $TMPBUILDDIR ; TZ=$TZ LANG=$LANG LC_ALL=$LC_ALL DESTDIR=$TMPDIR sudo make -j $NEW_NUM_CPU distribution" ) ; then
		# save results in b2
		save_freebsd_results b2
	else
		cleanup_tmpdirs
		echo "$(date -u ) - failed to build FreeBSD (branch $FREEBSD_TARGET at ${FREEBSD_VERSION[$FREEBSD_TARGET]}) in the second run."
	fi

	# set time back to today
	$RSSH "sudo ntpdate -b pool.ntp.org ; sudo service ntpd start ; sudo service ntpd status ; date"
	echo "$(date -u) - system is running at the current date now."

	# reset environment to default values again
	export LANG="en_GB.UTF-8"
	unset LC_ALL
	export TZ="/usr/share/zoneinfo/UTC"
	export PATH="/usr/sbin:/usr/bin:/sbin:/bin:/usr/games:"
	umask 0022
	run_diffoscope_on_results

done

#
#  finally create the webpage
#
cd $TMPDIR ; mkdir freebsd
PAGE=freebsd/freebsd.html
cat > $PAGE <<- EOF
<!DOCTYPE html>
<html lang="en-US">
  <head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width">
    <title>Reproducible FreeBSD ?</title>
    <link rel='stylesheet' href='global.css' type='text/css' media='all' />
  </head>
  <body>
    <div id="logo">
      <img src="320px-Freebsd_logo.svg.png" />
      <h1>Reproducible FreeBSD ?</h1>
    </div>
    <div class="content">
      <div class="page-content">
EOF
write_page_intro FreeBSD
for FREEBSD_TARGET in ${FREEBSD_TARGETS} ;do
	write_page "       <p>${GOOD_FILES[$FREEBSD_TARGET]} (${GOOD_PERCENT[$FREEBSD_TARGET]}%) out of ${ALL_FILES[$FREEBSD_TARGET]} FreeBSD files were reproducible in our test setup"
	if [ "${GOOD_PERCENT[$FREEBSD_TARGET]}" = "100.0" ] ; then
		write_page "!"
	else
		write_page "."
	fi
	write_page "        These tests were last run on $DATE for the branch $FREEBSD_TARGET at commit ${FREEBSD_VERSION[$FREEBSD_TARGET]} using ${DIFFOSCOPE}.</p>"
done
write_explaination_table FreeBSD
set -x
for FREEBSD_TARGET in ${FREEBSD_TARGETS} ;do
	ls ${FILES_HTML[$FREEBSD_TARGET]}
	cat ${FILES_HTML[$FREEBSD_TARGET]} >> $PAGE
	write_page "     <p><pre>"
	echo -n "${FREEBSD[$FREEBSD_TARGET]}" >> $PAGE
	write_page "     </pre></p>"
	write_page "    </div></div>"
	rm -f ${FILES_HTML[$FREEBSD_TARGET]}
done
set +x
write_page_footer FreeBSD
publish_page

# the end
calculate_build_duration
print_out_duration
FREEBSD_TARGET="master"
irc_message "$REPRODUCIBLE_URL/freebsd/ has been updated. (${GOOD_PERCENT[$FREEBSD_TARGET]}% reproducible)"
echo "============================================================================="

# remove everything, we don't need it anymore...
cleanup_tmpdirs
trap - INT TERM EXIT
