#!/bin/bash

# Copyright 2014-2015 Holger Levsen <holger@layer-acht.org>
#         © 2015 Mattia Rizzolo <mattia@mapreri.org>
# released under the GPLv=2

DEBUG=false
. /srv/jenkins/bin/common-functions.sh
common_init "$@"

# common code defining db access
. /srv/jenkins/bin/reproducible_common.sh

set -e

# build for these architectures
MACHINES="sparc64 amd64"

cleanup_tmpdirs() {
	cd
	$RSSH "rm -r $TMPDIR"
	$RSSH "rm -r $TMPBUILDDIR"
}

create_results_dirs() {
	mkdir -p $BASE/freebsd/dbd
}

save_freebsd_results(){
	local RUN=$1
	local MACHINE=$2
	mkdir -p $TMPDIR/$RUN/${MACHINE}
	cp -pr obj/releasedir/${MACHINE} $TMPDIR/$RUN/
	find $TMPDIR/$RUN/ -name MD5 -o -name SHA512 -exec rm {} \;
}

#
# main
#
RSSH="ssh freebsd-jenkins.debian.net"
TMPBUILDDIR=$($RSSH 'TMPDIR=/srv/workspace/chroots/ mktemp -d -t freebsd-XXXXXXXX')  # FIXME: not used to build on tmpfs
TMPDIR=$($RSSH 'TMPDIR=/srv/reproducible-results mktemp -d')  # used to compare results
DATE=$(date -u +'%Y-%m-%d')
START=$(date +'%s')
trap cleanup_tmpdirs INT TERM EXIT


echo "============================================================================="
echo "$(date -u) - Cloning the freebsd git repository (which is autosynced with their CVS repository)"
echo "============================================================================="
$RSSH git clone https://github.com/freebsd/freebsd.git $TMPBUILDDIR/freebsd
FREEBSD=$($RSSH "cd $TMPBUILDDIR/freebsd ; git log -1")
FREEBSD_VERSION=$($RSSH "cd $TMPBUILDDIR/freebsd ; git describe --always")
echo "This is freebsd $FREEBSD_VERSION."
echo
$RSSH "cd $TMPBUILDDIR/freebsd ; git log -1"


echo "so far so good, to be continued..."
echo
exit 1

echo "============================================================================="
echo "$(date -u) - Building freebsd ${FREEBSD_VERSION} - first build run."
echo "============================================================================="
export TZ="/usr/share/zoneinfo/Etc/GMT+12"
# actually build everything
for MACHINE in $MACHINES ; do
	ionice -c 3 nice \
		./build.sh -j $NUM_CPU -U -u -m ${MACHINE} release
	# save results in b1
	save_freebsd_results b1 ${MACHINE}
	# cleanup and explicitly delete old tooldir to force re-creation for the next $MACHINE type
	./build.sh -U -m ${MACHINE} cleandir
	rm obj/tooldir.* -rf
	echo "${MACHINE} done, first time."
done

echo "============================================================================="
echo "$(date -u) - Building freebsd ${FREEBSD_VERSION} - cleaning up between builds."
echo "============================================================================="
rm obj/releasedir -r
rm obj/destdir.* -r
# we keep the toolchain(s)

echo "============================================================================="
echo "$(date -u) - Building freebsd - second build run."
echo "============================================================================="
export TZ="/usr/share/zoneinfo/Etc/GMT-14"
export LANG="fr_CH.UTF-8"
export LC_ALL="fr_CH.UTF-8"
export PATH="/usr/sbin:/usr/bin:/sbin:/bin:/usr/games:/i/capture/the/path"
export CAPTURE_ENVIRONMENT="I capture the environment"
umask 0002
# use allmost all cores for second build
NEW_NUM_CPU=$(echo $NUM_CPU-1|bc)
for MACHINE in $MACHINES ; do
	ionice -c 3 nice \
		linux64 --uname-2.6 \
		./build.sh -j $NEW_NUM_CPU -U -u -m ${MACHINE} release
	# save results in b2
	save_freebsd_results b2 ${MACHINE}
	# cleanup and explicitly delete old tooldir to force re-creation for the next $MACHINE type
	./build.sh -U -m ${MACHINE} cleandir
	rm obj/tooldir.* -r
	echo "${MACHINE} done, second time."
done

# reset environment to default values again
export LANG="en_GB.UTF-8"
unset LC_ALL
export TZ="/usr/share/zoneinfo/UTC"
export PATH="/usr/sbin:/usr/bin:/sbin:/bin:/usr/games:"
umask 0022

# clean up builddir to save space on tmpfs
rm -r $TMPBUILDDIR/freebsd

# run debbindiff on the results
TIMEOUT="30m"
DBDSUITE="unstable"
DBDVERSION="$(schroot --directory /tmp -c source:jenkins-reproducible-${DBDSUITE}-debbindiff debbindiff -- --version 2>&1)"
echo "============================================================================="
echo "$(date -u) - Running $DBDVERSION on freebsd..."
echo "============================================================================="
FILES_HTML=$(mktemp --tmpdir=$TMPDIR)
echo "       <ul>" > $FILES_HTML
GOOD_FILES=0
ALL_FILES=0
SIZE=""
create_results_dirs
cd $TMPDIR/b1
tree .
for i in * ; do
	cd $i
	echo "       <table><tr><th>Release files for <code>$i</code></th></tr>" >> $FILES_HTML
	for j in $(find * -type f |sort -u ) ; do
		let ALL_FILES+=1
		call_debbindiff $i $j
		get_filesize $j
		if [ -f $TMPDIR/$i/$j.html ] ; then
			mkdir -p $BASE/freebsd/dbd/$i/$(dirname $j)
			mv $TMPDIR/$i/$j.html $BASE/freebsd/dbd/$i/$j.html
			echo "         <tr><td><a href=\"dbd/$i/$j.html\"><img src=\"/userContent/static/weather-showers-scattered.png\" alt=\"unreproducible icon\" /> $j</a> ($SIZE) is unreproducible.</td></tr>" >> $FILES_HTML
		else
			SHASUM=$(sha256sum $j|cut -d " " -f1)
			echo "         <tr><td><img src=\"/userContent/static/weather-clear.png\" alt=\"reproducible icon\" /> $j ($SHASUM, $SIZE) is reproducible.</td></tr>" >> $FILES_HTML
			let GOOD_FILES+=1
			rm -f $BASE/freebsd/dbd/$i/$j.html # cleanup from previous (unreproducible) tests - if needed
		fi
	done
	cd ..
	echo "       </table>" >> $FILES_HTML
done
GOOD_PERCENT=$(echo "scale=1 ; ($GOOD_FILES*100/$ALL_FILES)" | bc)
# are we there yet?
if [ "$GOOD_PERCENT" = "100.0" ] ; then
	MAGIC_SIGN="!"
else
	MAGIC_SIGN="?"
fi

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
    <title>Reproducible FreeBSD $MAGIC_SIGN</title>
    <link rel='stylesheet' href='global.css' type='text/css' media='all' />
  </head>
  <body>
    <div id="logo">
      <img src="FreeBSD-smaller.png" />
      <h1>Reproducible FreeBSD $MAGIC_SIGN</h1>
    </div>
    <div class="content">
      <div class="page-content">
EOF
write_page_intro FreeBSD
write_page "       <p>$GOOD_FILES ($GOOD_PERCENT%) out of $ALL_FILES built freebsd files were reproducible in our test setup"
if [ "$GOOD_PERCENT" = "100.0" ] ; then
	write_page "!"
else
	write_page "."
fi
write_page "        These tests were last run on $DATE for version ${FREEBSD_VERSION} using ${DBDVERSION}.</p>"
write_explaination_table FreeBSD
cat $FILES_HTML >> $PAGE
write_page "     <p><pre>"
echo -n "$FREEBSD" >> $PAGE
write_page "     </pre></p>"
write_page "    </div></div>"
write_page_footer FreeBSD
publish_page
rm -f $FILES_HTML 

# the end
calculate_build_duration
print_out_duration
irc_message "$REPRODUCIBLE_URL/freebsd/ has been updated. ($GOOD_PERCENT% reproducible)"
echo "============================================================================="

# remove everything, we don't need it anymore...
cleanup_tmpdirs
trap - INT TERM EXIT
