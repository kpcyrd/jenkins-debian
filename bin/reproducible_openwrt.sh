#!/bin/bash

# Copyright 2014-2015 Holger Levsen <holger@layer-acht.org>
#         © 2015 Mattia Rizzolo <mattia@mapreri.org>
# released under the GPLv=2

DEBUG=true
. /srv/jenkins/bin/common-functions.sh
common_init "$@"

# common code defining db access
. /srv/jenkins/bin/reproducible_common.sh
set -e

cleanup_tmpdir() {
	cd
	rm -r $TMPDIR
}

create_results_dirs() {
	mkdir -p $BASE/openwrt/dbd
}

call_debbindiff() {
	mkdir -p $TMPDIR/$1
	local TMPLOG=(mktemp --tmpdir=$TMPDIR)
	local msg=""
	set +e
	( timeout $TIMEOUT schroot \
		--directory $TMPDIR \
		-c source:jenkins-reproducible-${DBDSUITE}-debbindiff \
		debbindiff -- \
			--html $TMPDIR/$1/$2.html \
			$TMPDIR/b1/$1/$2 \
			$TMPDIR/b2/$1/$2 2>&1 \
	) 2>&1 >> $TMPLOG
	RESULT=$?
	if ! "$DEBUG" ; then set +x ; fi
	set -e
	cat $TMPLOG # print dbd output
	rm -f $TMPLOG
	case $RESULT in
		0)	echo "$(date -u) - $1/$2 is reproducible, yay!"
			;;
		1)
			echo "$(date -u) - $DBDVERSION found issues, please investigate $1/$2"
			;;
		2)
			msg="$(date -u) - $DBDVERSION had trouble comparing the two builds. Please investigate $1/$2"
			;;
		124)
			if [ ! -s $TMPDIR/$1.html ] ; then
				msg="$(date -u) - $DBDVERSION produced no output for $1/$2 and was killed after running into timeout after ${TIMEOUT}..."
			else
				msg="$DBDVERSION was killed after running into timeout after $TIMEOUT, but there is still $TMPDIR/$1/$2.html"
			fi
			;;
		*)
			msg="$(date -u) - Something weird happened when running $DBDVERSION on $1/$2 (which exited with $RESULT) and I don't know how to handle it."
			;;
	esac
	if [ ! -z $msg ] ; then
		echo $msg | tee -a $TMPDIR/$1/$2.html
	fi
}

#
# main
#

TMPDIR=$(mktemp --tmpdir=/srv/reproducible-results -d)  # where everything actually happens
trap cleanup_tmpdir INT TERM EXIT
cd $TMPDIR

DATE=$(date -u +'%Y-%m-%d')
START=$(date +'%s')
mkdir b1 b2

echo "============================================================================="
echo "$(date -u) - Cloning the OpenWRT git repository now."
echo "============================================================================="
git clone git://git.openwrt.org/openwrt.git
cd openwrt
OPENWRT="$(git log -1)"
OPENWRT_VERSION=$(git describe --always)
echo "This is openwrt $OPENWRT_VERSION."
echo
git log -1

echo "============================================================================="
echo "$(date -u) - Building the toolchain now."
echo "============================================================================="
make defconfig
nice ionice -c 3 \
	make -j $NUM_CPU tools/install
nice ionice -c 3 \
	make -j $NUM_CPU toolchain/install

echo "============================================================================="
echo "$(date -u) - Building openwrt ${OPENWRT_VERSION} images now - first build run."
echo "============================================================================="
export TZ="/usr/share/zoneinfo/Etc/GMT+12"
# actually build everything
#nice ionice -c 3 \
#	make
nice ionice -c 3 \
	make target/compile
nice ionice -c 3 \
	make -j $NUM_CPU package/cleanup
nice ionice -c 3 \
	make -j $NUM_CPU package/compile
nice ionice -c 3 \
	make -j $NUM_CPU package/install
nice ionice -c 3 \
	make -j $NUM_CPU target/install
nice ionice -c 3 \
	make -j $NUM_CPU package/index

cd bin
for i in * ; do
	cd $i
	mkdir $TMPDIR/b1/$i
	for j in $(find . -name "*.bin") ; do
		cp -p $j $TMPDIR/b1/$i/
	done
	cd ..
done
cd ..
rm bin -r

#
# clean up between builds
#
rm build_dir/target-* -r
rm taging_dir/target-* -r

echo "============================================================================="
echo "$(date -u) - Building openwrt images now - second build run."
echo "============================================================================="
export TZ="/usr/share/zoneinfo/Etc/GMT-14"
export LANG="fr_CH.UTF-8"
export LC_ALL="fr_CH.UTF-8"
export PATH="/usr/sbin:/usr/bin:/sbin:/bin:/usr/games:/i/capture/the/path"
export CAPTURE_ENVIRONMENT="I capture the environment"
umask 0002
# use allmost all cores for second build
NEW_NUM_CPU=$(echo $NUM_CPU-1|bc)
#nice ionice -c 3 \
#	linux64 --uname-2.6 \
#		make
nice ionice -c 3 \
	linux64 --uname-2.6 \
		make target/compile
nice ionice -c 3 \
	linux64 --uname-2.6 \
		make -j $NEW_NUM_CPU package/cleanup
nice ionice -c 3 \
	linux64 --uname-2.6 \
		make -j $NEW_NUM_CPU package/compile
nice ionice -c 3 \
	linux64 --uname-2.6 \
		make -j $NEW_NUM_CPU package/install
nice ionice -c 3 \
	linux64 --uname-2.6 \
		make -j $NEW_NUM_CPU target/install
nice ionice -c 3 \
	linux64 --uname-2.6 \
		make -j $NEW_NUM_CPU package/index

# reset environment to default values again
export LANG="en_GB.UTF-8"
unset LC_ALL
export TZ="/usr/share/zoneinfo/UTC"
export PATH="/usr/sbin:/usr/bin:/sbin:/bin:/usr/games:"
umask 0022

cd bin
for i in * ; do
	cd $i
	mkdir $TMPDIR/b2/$i
	for j in $(find . -name "*.bin") ; do
		cp -p $j $TMPDIR/b2/$i/
	done
	cd ..
done
cd ..
rm bin -r

#
# create html about toolchain used
#
TOOLCHAIN_HTML=$(mktemp)
TARGET=$(ls -1d staging_dir/toolchain*|cut -d "-" -f2-)
echo "<table><tr><th>Contents of <pre>build_dir/host/</pre></th></tr>" > $TOOLCHAIN_HTML
for i in $(ls -1 build_dir/host/) ; do
	echo " <tr><td>$i</td></tr>" >> $TOOLCHAIN_HTML
echo "</table>" >> $TOOLCHAIN_HTML
echo "<table><tr><th>Downloaded software built for <pre>$TARGET</pre></th></tr>" >> $TOOLCHAIN_HTML
for i in $(ls -1 dl/) ; do
	echo " <tr><td>$i</td></tr>" >> $TOOLCHAIN_HTML
echo "</table>" >> $TOOLCHAIN_HTML
echo "<table><tr><th>Debian $(cat /etc/debian_version) package on $(dpkg --print-architecture)</th><th>installed version</th></tr>" >> $TOOLCHAIN_HTML
for i in gcc binutils bzip2 flex python perl make findutils grep diff unzip gawk util-linux zlib1g-dev libc6-dev git subversion ; do
	echo " <tr><td>$i</td><td>" >> $TOOLCHAIN_HTML
	dpkg -s $i|grep '^Version'|cut -d " " -f2 >> $TOOLCHAIN_HTML
	echo " </td></tr>" >> $TOOLCHAIN_HTML
done
echo "</table>" >> $TOOLCHAIN_HTML

# run debbindiff on the results
TIMEOUT="30m"
DBDSUITE="unstable"
DBDVERSION="$(schroot --directory /tmp -c source:jenkins-reproducible-${DBDSUITE}-debbindiff debbindiff -- --version 2>&1)"
echo "============================================================================="
echo "$(date -u) - Running $DBDVERSION on openwrt images now"
echo "============================================================================="
IMAGES_HTML=$(mktemp)
echo "       <ul>" > $IMAGES_HTML
GOOD_IMAGES=0
ALL_IMAGES=0
create_results_dirs
cd $TMPDIR/b1
for i in * ; do
	cd $i
	for j in $(find . -name "*.bin") ; do
		let ALL_IMAGES+=1
		call_debbindiff $i $j
		SIZE="$(du -h -b $j | cut -f1)"
		SIZE="$(echo $SIZE/1024|bc)"
		if [ -f $TMPDIR/$i/$j.html ] ; then
			mkdir -p $BASE/openwrt/dbd/$i
			mv $TMPDIR/$i/$j.html $BASE/openwrt/dbd/$i/$j.html
			echo "         <li><a href=\"dbd/$i/$j.html\"><img src=\"/userContent/static/weather-showers-scattered.png\" alt=\"unreproducible icon\" /> $j</a> (${SIZE}K) is unreproducible.</li>" >> $IMAGES_HTML
		else
			SHASUM=$(sha256sum $j|cut -d " " -f1)
			echo "         <li><img src=\"/userContent/static/weather-clear.png\" alt=\"reproducible icon\" /> $j ($SHASUM, ${SIZE}K) is reproducible.</li>" >> $IMAGES_HTML
			let GOOD_IMAGES+=1
			rm -f $BASE/openwrt/dbd/$i/$j.html # cleanup from previous (unreproducible) tests - if needed
		fi
	done
	cd ..
done
echo "       </ul>" >> $IMAGES_HTML
GOOD_PERCENT=$(echo "scale=1 ; ($GOOD_IMAGES*100/$ALL_IMAGES)" | bc)

#
#  finally create the webpage
#
cd $TMPDIR
PAGE=openwrt/openwrt.html
cat > $PAGE <<- EOF
<!DOCTYPE html>
<html lang="en-US">
  <head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width">
    <title>openwrt</title>
    <!-- link rel='stylesheet' id='twentyfourteen-style-css'  href='landing_style.css?ver=4.0' type='text/css' media='all' /-->
  </head>
  <body>
    <div class="content">
      <div class="page-content">
        <p>&nbsp;</p>
        <p><center><img src="logo.png" alt="openwrt logo"" /><br />
        <blockquote>
	  <br />
          <strong>OpenWRT</strong>: <em>reproducible</em> wireless freedom?
        </blockquote>
        <pre>
EOF
cat $(find openwrt/build_dir/ -name banner | grep etc/banner|head -1) >> $PAGE
write_page "       </pre></center></p>"
write_page "       <h1>Reproducible OpenWRT</h1>"
write_page "       <p><em>Reproducible builds</em> enable anyone to reproduce bit by bit identical binary packages from a given source, so that anyone can verify that a given binary derived from the source it was said to be derived. There is a lot more information about <a href=\"https://wiki.debian.org/ReproducibleBuilds\">reproducible builds on the Debian wiki</a> and on <a href=\"https://reproducible.debian.net\">https://reproducible.debian.net</a>. The wiki has a lot more information, eg. why this is useful, what common issues exist and which workarounds and solutions are known.<br />"
write_page "        <em>Reproducible OpenWRT</em> is an effort to apply this to OpenWRT. Thus each OpenWR target is build twice, with a few varitations added and then the resulting images from the two builds are compared using <a href=\"https://tracker.debian.org/debbindiff\">debbindiff</a>. Please note that the toolchain is not varied at all as the rebuild happens on exactly the same system. More variations are expected to be seen in the wild.</p>"
write_page "       <p>There is a monthly run <a href=\"https://jenkins.debian.net/view/reproducible/job/reproducible_openwrt/\">jenkins job</a> to test the <code>master</code> branch of <a href=\"git://git.openwrt.org/openwrt.git\">openwrt.git</a>. Currently this job is triggered more often though, because this is still under development and brand new. The jenkins job is simply running <a href=\"http://anonscm.debian.org/cgit/qa/jenkins.debian.net.git/tree/bin/reproducible_openwrt.sh\">reproducible_openwrt.sh</a> in a Debian environemnt and this script is solely responsible for creating this page. Feel invited to join <code>#debian-reproducible</code> (on irc.oftc.net) to request job runs whenever sensible. Patches and other <a href=\"mailto:reproducible-builds@lists.alioth.debian.org\">feedback</a> are very much appreciated!</p>"
write_page "       <p>$GOOD_IMAGES ($GOOD_PERCENT%) out of $ALL_IMAGES built openwrt images were reproducible in our test setup."
write_page "        These tests were last run on $DATE for version ${OPENWRT_VERSION}.</p>"
write_explaination_table OpenWRT
cat $IMAGES_HTML >> $PAGE
write_page "     <p><pre>"
echo -n "$OPENWRT" >> $PAGE
write_page "     </pre></p>"
cat $TOOLCHAIN_HTML >> $PAGE
write_page "    </div></div>"
write_page_footer OpenWRT
publish_page
rm -f $IMAGES_HTML $TOOLCHAIN_HTML

# the end
calculate_build_duration
print_out_duration
irc_message "$REPRODUCIBLE_URL/openwrt/ has been updated. ($GOOD_PERCENT% reproducible)"
echo "============================================================================="

# remove everything, we don't need it anymore...
cleanup_tmpdir
trap - INT TERM EXIT
