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

cleanup_tmpdirs() {
	cd
	rm -r $TMPDIR
	rm -r $TMPBUILDDIR
}

create_results_dirs() {
	mkdir -p $BASE/openwrt/dbd
}

call_debbindiff() {
	mkdir -p $TMPDIR/$1/$(dirname $2)
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

save_openwrt_results(){
	RUN=$1
	cd bin
	for i in * ; do
		cd $i
		# save images
		mkdir -p $TMPDIR/$RUN/$i
		for j in $(find * -name "*.bin" -o -name "*.squashfs") ; do
			cp -p $j $TMPDIR/$RUN/$i/
		done
		# save packages
		cd packages
		for j in $(find * -name "*.ipk") ; do
			mkdir -p $TMPDIR/$RUN/$i/$(dirname $j)
			cp -p $j $TMPDIR/$RUN/$i/$(dirname $j)/
		done
		cd ../..
	done
	cd ..
}

openwrt_config() {
	TARGET=$1

	echo "CONFIG_TARGET_$TARGET=y" > .config
	make defconfig
}

openwrt_build_toolchain() {
	echo "============================================================================="
	echo "$(date -u) - Building the toolchain."
	echo "============================================================================="

	ionice -c 3 nice \
		make -j $NUM_CPU tools/install
	ionice -c 3 nice \
		make -j $NUM_CPU toolchain/install
}

openwrt_build() {
	RUN=$1
	TARGET=$2

	echo "============================================================================="
	echo "$(date -u) - Building OpenWrt ${OPENWRT_VERSION} ($TARGET) - $RUN build run."
	echo "============================================================================="
	ionice -c 3 nice \
		$MAKE -j $NUM_CPU target/compile
	ionice -c 3 nice \
		$MAKE -j $NUM_CPU package/cleanup
	ionice -c 3 nice \
		$MAKE -j $NUM_CPU package/compile || true # don't let some packages fail the whole build
	ionice -c 3 nice \
		$MAKE -j $NUM_CPU package/install
	ionice -c 3 nice \
		$MAKE -j $NUM_CPU target/install
	ionice -c 3 nice \
		$MAKE -j $NUM_CPU package/index
}

openwrt_cleanup() {
	rm build_dir/target-* -r
	rm staging_dir/target-* -r
	rm bin/* -r
}

build_two_times() {
	$TARGET=$1
	openwrt_config $TARGET
	openwrt_build_toolchain

	# FIRST BUILD
	export TZ="/usr/share/zoneinfo/Etc/GMT+12"
	MAKE=make

	# first build
	openwrt_build "first" "$TARGET"

	# save results in b1
	save_openwrt_results b1

	# clean up between builds
	openwrt_cleanup

	# SECOND BUILD
	export TZ="/usr/share/zoneinfo/Etc/GMT-14"
	export LANG="fr_CH.UTF-8"
	export LC_ALL="fr_CH.UTF-8"
	export PATH="/usr/sbin:/usr/bin:/sbin:/bin:/usr/games:/i/capture/the/path"
	export CAPTURE_ENVIRONMENT="I capture the environment"
	umask 0002
	# use allmost all cores for second build
	NEW_NUM_CPU=$(echo $NUM_CPU-1|bc)
	MAKE="linux64 --uname-2.6 make"
	openwrt_build "second" "$TARGET"

	# save results in b2
	save_openwrt_results b2

	# reset environment to default values again
	export LANG="en_GB.UTF-8"
	unset LC_ALL
	export TZ="/usr/share/zoneinfo/UTC"
	export PATH="/usr/sbin:/usr/bin:/sbin:/bin:/usr/games:"
	umask 0022
}

#
# main
#
TMPBUILDDIR=$(mktemp --tmpdir=/srv/workspace/chroots/ -d -t openwrt-XXXXXXXX)  # used to build on tmpfs
TMPDIR=$(mktemp --tmpdir=/srv/reproducible-results -d)  # accessable in schroots, used to compare results
DATE=$(date -u +'%Y-%m-%d')
START=$(date +'%s')
trap cleanup_tmpdirs INT TERM EXIT

cd $TMPBUILDDIR
echo "============================================================================="
echo "$(date -u) - Cloning the OpenWrt git repository."
echo "============================================================================="
git clone git://git.openwrt.org/openwrt.git
cd openwrt
OPENWRT="$(git log -1)"
OPENWRT_VERSION=$(git describe --always)
echo "This is openwrt $OPENWRT_VERSION."
echo
git log -1

echo "============================================================================="
echo "$(date -u) - Updating package feeds."
echo "============================================================================="
./scripts/feeds update -a
./scripts/feeds install -a

build_two_times ar71xx_generic_ARCHERC7
build_two_times x86_64
build_two_times ramips_rt288x_RTN15

#
# create html about toolchain used
#
TOOLCHAIN_HTML=$(mktemp --tmpdir=$TMPDIR)
TARGET=$(ls -1d staging_dir/toolchain*|cut -d "-" -f2-|xargs echo)
echo "<table><tr><th>Contents of <code>build_dir/host/</code></th></tr>" > $TOOLCHAIN_HTML
for i in $(ls -1 build_dir/host/) ; do
	echo " <tr><td>$i</td></tr>" >> $TOOLCHAIN_HTML
done
echo "</table>" >> $TOOLCHAIN_HTML
echo "<table><tr><th>Downloaded software built for <code>$TARGET</code></th></tr>" >> $TOOLCHAIN_HTML
for i in $(ls -1 dl/) ; do
	echo " <tr><td>$i</td></tr>" >> $TOOLCHAIN_HTML
done
echo "</table>" >> $TOOLCHAIN_HTML
echo "<table><tr><th>Debian $(cat /etc/debian_version) package on $(dpkg --print-architecture)</th><th>installed version</th></tr>" >> $TOOLCHAIN_HTML
for i in gcc binutils bzip2 flex python perl make findutils grep diffutils unzip gawk util-linux zlib1g-dev libc6-dev git subversion ; do
	echo " <tr><td>$i</td><td>" >> $TOOLCHAIN_HTML
	dpkg -s $i|grep '^Version'|cut -d " " -f2 >> $TOOLCHAIN_HTML
	echo " </td></tr>" >> $TOOLCHAIN_HTML
done
echo "</table>" >> $TOOLCHAIN_HTML
# get banner
BANNER_HTML=$(mktemp --tmpdir=$TMPDIR)
cat $(find build_dir/ -name banner | grep etc/banner|head -1) >> $BANNER_HTML

# clean up builddir to save space on tmpfs
rm -r $TMPBUILDDIR/openwrt

# run debbindiff on the results
# (this needs refactoring rather badly)
TIMEOUT="30m"
DBDSUITE="unstable"
DBDVERSION="$(schroot --directory /tmp -c source:jenkins-reproducible-${DBDSUITE}-debbindiff debbindiff -- --version 2>&1)"
echo "============================================================================="
echo "$(date -u) - Running $DBDVERSION on OpenWrt images and packages."
echo "============================================================================="
DBD_HTML=$(mktemp --tmpdir=$TMPDIR)
# run debbindiff on the images
echo "       <table><tr><th>Images for <code>$TARGET</code></th></tr>" > $DBD_HTML
GOOD_IMAGES=0
ALL_IMAGES=0
create_results_dirs
cd $TMPDIR/b1
for i in * ; do
	cd $i
	for j in $(find * -name "*.bin" -o -name "*.squashfs" |sort -u ) ; do
		let ALL_IMAGES+=1
		call_debbindiff $i $j
		SIZE="$(du -h -b $j | cut -f1)"
		SIZE="$(echo $SIZE/1024|bc)"
		if [ -f $TMPDIR/$i/$j.html ] ; then
			mkdir -p $BASE/openwrt/dbd/$i
			mv $TMPDIR/$i/$j.html $BASE/openwrt/dbd/$i/$j.html
			echo "         <tr><td><a href=\"dbd/$i/$j.html\"><img src=\"/userContent/static/weather-showers-scattered.png\" alt=\"unreproducible icon\" /> $j</a> (${SIZE}K) is unreproducible.</td></tr>" >> $DBD_HTML
		else
			SHASUM=$(sha256sum $j|cut -d " " -f1)
			echo "         <tr><td><img src=\"/userContent/static/weather-clear.png\" alt=\"reproducible icon\" /> $j ($SHASUM, ${SIZE}K) is reproducible.</td></tr>" >> $DBD_HTML
			let GOOD_IMAGES+=1
			rm -f $BASE/openwrt/dbd/$i/$j.html # cleanup from previous (unreproducible) tests - if needed
		fi
	done
	cd ..
done
echo "       </table>" >> $DBD_HTML
GOOD_PERCENT_IMAGES=$(echo "scale=1 ; ($GOOD_IMAGES*100/$ALL_IMAGES)" | bc)
# run debbindiff on the packages
echo "       <table><tr><th>Packages for <code>$TARGET</code></th></tr>" >> $DBD_HTML
GOOD_PACKAGES=0
ALL_PACKAGES=0
create_results_dirs
cd $TMPDIR/b1
tree .
for i in * ; do
	cd $i
	for j in $(find * -name "*.ipk" |sort -u ) ; do
		let ALL_PACKAGES+=1
		call_debbindiff $i $j
		SIZE="$(du -h -b $j | cut -f1)"
		SIZE="$(echo $SIZE/1024|bc)"
		if [ -f $TMPDIR/$i/$j.html ] ; then
			mkdir -p $BASE/openwrt/dbd/$i/$(dirname $j)
			mv $TMPDIR/$i/$j.html $BASE/openwrt/dbd/$i/$j.html
			echo "         <tr><td><a href=\"dbd/$i/$j.html\"><img src=\"/userContent/static/weather-showers-scattered.png\" alt=\"unreproducible icon\" /> $j</a> (${SIZE}K) is unreproducible.</td></tr>" >> $DBD_HTML
		else
			SHASUM=$(sha256sum $j|cut -d " " -f1)
			echo "         <tr><td><img src=\"/userContent/static/weather-clear.png\" alt=\"reproducible icon\" /> $j ($SHASUM, ${SIZE}K) is reproducible.</td></tr>" >> $DBD_HTML
			let GOOD_PACKAGES+=1
			rm -f $BASE/openwrt/dbd/$i/$j.html # cleanup from previous (unreproducible) tests - if needed
		fi
	done
	cd ..
done
echo "       </table>" >> $DBD_HTML
GOOD_PERCENT_PACKAGES=$(echo "scale=1 ; ($GOOD_PACKAGES*100/$ALL_PACKAGES)" | bc)
# are we there yet?
if [ "$GOOD_PERCENT_IMAGES" = "100.0" ] || [ "$GOOD_PERCENT_PACKAGES" = "100.0" ]; then
	MAGIC_SIGN="!"
else
	MAGIC_SIGN="?"
fi

#
#  finally create the webpage
#
cd $TMPDIR ; mkdir openwrt
PAGE=openwrt/openwrt.html
cat > $PAGE <<- EOF
<!DOCTYPE html>
<html lang="en-US">
  <head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width">
    <title>openwrt</title>
    <link rel='stylesheet' id='kamikaze-style-css'  href='cascade.css?ver=4.0' type='text/css' media='all'>
  </head>
  <body>
    <div id="header">
        <p><center>
        <code>
EOF
cat $BANNER_HTML >> $PAGE
write_page "       </code></center></p>"
write_page "     </div><div id=\"main-content\">"
write_page "       <h1>OpenWrt - <em>reproducible</em> wireless freedom$MAGIC_SIGN</h1>"
write_page "       <p><em>Reproducible builds</em> enable anyone to reproduce bit by bit identical binary packages from a given source, so that anyone can verify that a given binary derived from the source it was said to be derived. There is a lot more information about <a href=\"https://wiki.debian.org/ReproducibleBuilds\">reproducible builds on the Debian wiki</a> and on <a href=\"https://reproducible.debian.net\">https://reproducible.debian.net</a>. The wiki has a lot more information, eg. why this is useful, what common issues exist and which workarounds and solutions are known.<br />"
write_page "        <em>Reproducible OpenWrt</em> is an effort to apply this to OpenWrt Thus each OpenWR target is build twice, with a few varitations added and then the resulting images from the two builds are compared using <a href=\"https://tracker.debian.org/debbindiff\">debbindiff</a>, <em>which currently cannot detect <code>.bin</code> files as squashfs filesystems.</em> Thus the resulting debbindiff output is not nearly as clear as it could be - hopefully this limitation will be overcome soon. Also please note that the toolchain is not varied at all as the rebuild happens on exactly the same system. More variations are expected to be seen in the wild.</p>"
write_page "       <p>There is a monthly run <a href=\"https://jenkins.debian.net/view/reproducible/job/reproducible_openwrt/\">jenkins job</a> to test the <code>master</code> branch of <a href=\"git://git.openwrt.org/openwrt.git\">openwrt.git</a>. Currently this job is triggered more often though, because this is still under development and brand new. The jenkins job is simply running <a href=\"http://anonscm.debian.org/cgit/qa/jenkins.debian.net.git/tree/bin/reproducible_openwrt.sh\">reproducible_openwrt.sh</a> in a Debian environment and this script is solely responsible for creating this page. Feel invited to join <code>#debian-reproducible</code> (on irc.oftc.net) to request job runs whenever sensible. Patches and other <a href=\"mailto:reproducible-builds@lists.alioth.debian.org\">feedback</a> are very much appreciated!</p>"
write_page "       <p>$GOOD_IMAGES ($GOOD_PERCENT_IMAGES%) out of $ALL_IMAGES built images and $GOOD_PACKAGES ($GOOD_PERCENT_PACKAGES%) out of $ALL_PACKAGES built packages were reproducible in our test setup."
write_page "        These tests were last run on $DATE for version ${OPENWRT_VERSION}.</p>"
write_explaination_table OpenWrt
cat $DBD_HTML >> $PAGE
write_page "     <table><tr><th>git commit built</th></tr><tr><td><code>"
echo -n "$OPENWRT" >> $PAGE
write_page "     </code></td></tr></table>"
cat $TOOLCHAIN_HTML >> $PAGE
write_page "    </div>"
write_page_footer OpenWrt
publish_page
rm -f $DBD_HTML $TOOLCHAIN_HTML $BANNER_HTML

# the end
calculate_build_duration
print_out_duration
irc_message "$REPRODUCIBLE_URL/openwrt/ has been updated. ($GOOD_PERCENT_IMAGES% images and $GOOD_PERCENT_PACKAGES% reproducible)"
echo "============================================================================="

# remove everything, we don't need it anymore...
cleanup_tmpdirs
trap - INT TERM EXIT
