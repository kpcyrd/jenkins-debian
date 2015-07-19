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
	CONFIG=$1

	printf "$CONFIG" > .config
	printf "CONFIG_ALL=y" >> .config
	make defconfig
}

openwrt_build_toolchain() {
	echo "============================================================================="
	echo "$(date -u) - Building the toolchain."
	echo "============================================================================="

	ionice -c 3 nice \
		make -j 1 V=s tools/install
		#make -j $NUM_CPU tools/install
	ionice -c 3 nice \
		make -j 1 V=s toolchain/install
		#make -j $NUM_CPU toolchain/install
}

openwrt_build() {
	RUN=$1
	TARGET=$2

	OPTIONS="-j $NUM_CPU IGNORE_ERRORS=1"

	echo "============================================================================="
	echo "$(date -u) - Building OpenWrt ${OPENWRT_VERSION} ($TARGET) - $RUN build run."
	echo "============================================================================="
	ionice -c 3 nice \
		$MAKE $OPTIONS target/compile
	ionice -c 3 nice \
		$MAKE $OPTIONS package/cleanup
	ionice -c 3 nice \
		$MAKE $OPTIONS package/compile || true # don't let some packages fail the whole build
	ionice -c 3 nice \
		$MAKE $OPTIONS package/install
	ionice -c 3 nice \
		$MAKE $OPTIONS target/install
	ionice -c 3 nice \
		$MAKE $OPTIONS package/index || true # don't let some packages fail the whole build
}

openwrt_cleanup() {
	rm build_dir/target-* -r
	rm staging_dir/target-* -r
	rm bin/* -r
}

build_two_times() {
	TARGET=$1
	CONFIG=$2
	openwrt_config $CONFIG
	openwrt_build_toolchain

	# FIRST BUILD
	export TZ="/usr/share/zoneinfo/Etc/GMT+12"
	MAKE=make
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

	# clean up again
	openwrt_cleanup
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

build_two_times ar71xx_generic_ARCHERC7 "CONFIG_TARGET_ar71xx_generic=y\nCONFIG_TARGET_ar71xx_generic_ARCHERC7=y\n"
build_two_times x86_64 "CONFIG_TARGET_x86=y\nCONFIG_TARGET_x86_64=y\n"
build_two_times ramips_rt288x_RTN15 "CONFIG_TARGET_ramips=y\nCONFIG_TARGET_ramips_rt288x=y\nCONFIG_TARGET_ramips_rt288x_RTN15=y\n"

#
# create html about toolchain used
#
TOOLCHAIN_HTML=$(mktemp --tmpdir=$TMPDIR)
echo "<table><tr><th>Target toolchains built</th></tr>" > $TOOLCHAIN_HTML
for i in $(ls -1d staging_dir/toolchain*|cut -d "-" -f2-|xargs echo) ; do
	echo " <tr><td><code>$i</code></td></tr>" >> $TOOLCHAIN_HTML
done
echo "</table>" >> $TOOLCHAIN_HTML
echo "<table><tr><th>Contents of <code>build_dir/host/</code></th></tr>" >> $TOOLCHAIN_HTML
for i in $(ls -1 build_dir/host/) ; do
	echo " <tr><td>$i</td></tr>" >> $TOOLCHAIN_HTML
done
echo "</table>" >> $TOOLCHAIN_HTML
echo "<table><tr><th>Downloaded software</th></tr>" >> $TOOLCHAIN_HTML
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
GOOD_IMAGES=0
ALL_IMAGES=0
SIZE=""
create_results_dirs
cd $TMPDIR/b1
tree .
for i in * ; do
	cd $i

	# search images in both paths to find non-existing ones
	IMGS1=$(find * -type f -name "*.bin" -o -name "*.squashfs" | sort -u )
	pushd $TMPDIR/b2/$i
	IMGS2=$(find * -type f -name "*.bin" -o -name "*.squashfs" | sort -u )
	popd

	echo "       <table><tr><th>Images for <code>$i</code></th></tr>" >> $DBD_HTML
	for j in $(printf "$IMGS1\n$IMGS2" | sort -u ) ; do
		let ALL_IMAGES+=1
		if [ ! -f $TMPDIR/b1/$i/$j -o ! -f $TMPDIR/b2/$i/$j ] ; then
			echo "         <tr><td><img src=\"/userContent/static/weather-storm.png\" alt=\"ftbfs icon\" /> $j (${SIZE}K) failed to build once.</td></tr>" >> $DBD_HTML
			rm -f $BASE/openwrt/dbd/$i/$j.html # cleanup from previous (unreproducible) tests - if needed
			continue
		fi
		call_debbindiff $i $j
		get_filesize $j
		if [ -f $TMPDIR/$i/$j.html ] ; then
			mkdir -p $BASE/openwrt/dbd/$i
			mv $TMPDIR/$i/$j.html $BASE/openwrt/dbd/$i/$j.html
			echo "         <tr><td><a href=\"dbd/$i/$j.html\"><img src=\"/userContent/static/weather-showers-scattered.png\" alt=\"unreproducible icon\" /> $j</a> (${SIZE}K) is unreproducible.</td></tr>" >> $DBD_HTML
		else
			SHASUM=$(sha256sum $j|cut -d " " -f1)
			echo "         <tr><td><img src=\"/userContent/static/weather-clear.png\" alt=\"reproducible icon\" /> $j ($SHASUM, $SIZE) is reproducible.</td></tr>" >> $DBD_HTML
			let GOOD_IMAGES+=1
			rm -f $BASE/openwrt/dbd/$i/$j.html # cleanup from previous (unreproducible) tests - if needed
		fi
	done
	cd ..
	echo "       </table>" >> $DBD_HTML
done
GOOD_PERCENT_IMAGES=$(echo "scale=1 ; ($GOOD_IMAGES*100/$ALL_IMAGES)" | bc)
# run debbindiff on the packages
GOOD_PACKAGES=0
ALL_PACKAGES=0
create_results_dirs
cd $TMPDIR/b1
for i in * ; do
	cd $i

	# search packages in both paths to find non-existing ones
	PKGS1=$(find * -type f -name "*.ipk" | sort -u )
	pushd $TMPDIR/b2/$i
	PKGS2=$(find * -type f -name "*.ipk" | sort -u )
	popd

	echo "       <table><tr><th>Packages for <code>$i</code></th></tr>" >> $DBD_HTML
	for j in $(printf "$PKGS1\n$PKGS2" | sort -u ) ; do
		let ALL_PACKAGES+=1
		if [ ! -f $TMPDIR/b1/$i/$j -o ! -f $TMPDIR/b2/$i/$j ] ; then
			echo "         <tr><td><img src=\"/userContent/static/weather-storm.png\" alt=\"ftbfs icon\" /> $j (${SIZE}K) failed to build once.</td></tr>" >> $DBD_HTML
			rm -f $BASE/openwrt/dbd/$i/$j.html # cleanup from previous (unreproducible) tests - if needed
			continue
		fi
		call_debbindiff $i $j
		get_filesize $j
		if [ -f $TMPDIR/$i/$j.html ] ; then
			mkdir -p $BASE/openwrt/dbd/$i/$(dirname $j)
			mv $TMPDIR/$i/$j.html $BASE/openwrt/dbd/$i/$j.html
			echo "         <tr><td><a href=\"dbd/$i/$j.html\"><img src=\"/userContent/static/weather-showers-scattered.png\" alt=\"unreproducible icon\" /> $j</a> ($SIZE) is unreproducible.</td></tr>" >> $DBD_HTML
		else
			SHASUM=$(sha256sum $j|cut -d " " -f1)
			echo "         <tr><td><img src=\"/userContent/static/weather-clear.png\" alt=\"reproducible icon\" /> $j ($SHASUM, $SIZE) is reproducible.</td></tr>" >> $DBD_HTML
			let GOOD_PACKAGES+=1
			rm -f $BASE/openwrt/dbd/$i/$j.html # cleanup from previous (unreproducible) tests - if needed
		fi
	done
	cd ..
	echo "       </table>" >> $DBD_HTML
done
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
    <title>Repoducible OpenWrt ?</title>
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
write_page_intro OpenWrt
write_page "       <p>$GOOD_IMAGES ($GOOD_PERCENT_IMAGES%) out of $ALL_IMAGES built images and $GOOD_PACKAGES ($GOOD_PERCENT_PACKAGES%) out of $ALL_PACKAGES built packages were reproducible in our test setup."
write_page "        These tests were last run on $DATE for version ${OPENWRT_VERSION} using ${DBDVERSION}.</p>"
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
irc_message "$REPRODUCIBLE_URL/openwrt/ has been updated. ($GOOD_PERCENT_IMAGES% images and $GOOD_PERCENT_PACKAGES% packages reproducible)"
echo "============================================================================="

# remove everything, we don't need it anymore...
cleanup_tmpdirs
trap - INT TERM EXIT
