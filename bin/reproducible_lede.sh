#!/bin/bash

# Copyright 2014-2017 Holger Levsen <holger@layer-acht.org>
#         © 2015 Reiner Herrmann <reiner@reiner-h.de>
#           2016-2017 Alexander Couzens <lynxis@fe80.eu>
# released under the GPLv=2

OPENWRT_GIT_REPO=https://git.lede-project.org/lede/lynxis/staging.git
OPENWRT_GIT_BRANCH=master
DEBUG=false
LEDE_CONFIG=
LEDE_TARGET=

. /srv/jenkins/bin/common-functions.sh
common_init "$@"

# common code defining db access
. /srv/jenkins/bin/reproducible_common.sh
# common code defining functions for OpenWrt/LEDE
. /srv/jenkins/bin/reproducible_lede_common.sh
set -e

echo "$0 got called with '$@'"
# this script is called from positions
# * it's called from the reproducible_wrapper when running on the master
# * it's called from reproducible_opewnrt_common when doing remote builds
case $1 in
	node)
		shift
		case $1 in
			openwrt_build |\
			openwrt_download |\
			openwrt_get_banner |\
			openwrt_get_commit |\
			node_create_tmpdirs |\
			node_debug |\
			node_save_logs |\
			node_cleanup_tmpdirs) ;; # this is the allowed list
			*)
				echo "Unsupported remote node function $@"
				exit 1
				;;
		esac
		$@
		trap - INT TERM EXIT
		exit 0
	;;
	master)
		# master code following
		LEDE_TARGET=$2
		LEDE_CONFIG=$3
	;;
	*)
		echo "Unsupported mode $1. Arguments are $@"
		exit 1
	;;
esac

#
# main
#
DATE=$(date -u +'%Y-%m-%d')
START=$(date +'%s')
TMPBUILDDIR=$(mktemp --tmpdir=/srv/workspace/chroots/ -d -t rbuild-lede-build-${DATE}-XXXXXXXX)  # used to build on tmpfs
TMPDIR=$(mktemp --tmpdir=/srv/reproducible-results -d -t rbuild-lede-results-XXXXXXXX)  # accessable in schroots, used to compare results
BANNER_HTML=$(mktemp --tmpdir=$TMPDIR)
GIT_COMMIT=$(mktemp --tmpdir=$TMPDIR)
trap master_cleanup_tmpdirs INT TERM EXIT

cd $TMPBUILDDIR

create_results_dirs lede

build_two_times lede "$LEDE_TARGET" "$LEDE_CONFIG"

# for now we only build one architecture until it's at most reproducible
#build_two_times x86_64 "CONFIG_TARGET_x86=y\nCONFIG_TARGET_x86_64=y\n"
#build_two_times ramips_rt288x_RTN15 "CONFIG_TARGET_ramips=y\nCONFIG_TARGET_ramips_rt288x=y\nCONFIG_TARGET_ramips_rt288x_RTN15=y\n"

#
# create html about toolchain used
#
echo "============================================================================="
echo "$(date -u) - Creating Documentation HTML"
echo "============================================================================="

# created & copied by build_two_times()
TOOLCHAIN_HTML=$TMPDIR/toolchain.html

# clean up builddir to save space on tmpfs
rm -rf $TMPBUILDDIR/lede

# run diffoscope on the results
# (this needs refactoring rather badly)
TIMEOUT="30m"
DIFFOSCOPE="$(schroot --directory /tmp -c source:jenkins-reproducible-${DBDSUITE}-diffoscope diffoscope -- --version 2>&1)"
echo "============================================================================="
echo "$(date -u) - Running $DIFFOSCOPE on LEDE images and packages."
echo "============================================================================="
DBD_HTML=$(mktemp --tmpdir=$TMPDIR)
DBD_GOOD_PKGS_HTML=$(mktemp --tmpdir=$TMPDIR)
DBD_BAD_PKGS_HTML=$(mktemp --tmpdir=$TMPDIR)
# run diffoscope on the images
GOOD_IMAGES=0
ALL_IMAGES=0
SIZE=""
cd $TMPDIR/b1/targets
tree .

# iterate over all images (merge b1 and b2 images into one list)
# call diffoscope on the images
for target in * ; do
	cd $target
	for subtarget in * ; do
		cd $subtarget

		# search images in both paths to find non-existing ones
		IMGS1=$(find * -type f -name "*.bin" -o -name "*.squashfs" | sort -u )
		pushd $TMPDIR/b2/targets/$target/$subtarget
		IMGS2=$(find * -type f -name "*.bin" -o -name "*.squashfs" | sort -u )
		popd

		echo "       <table><tr><th>Images for <code>$target/$subtarget</code></th></tr>" >> $DBD_HTML
		for image in $(printf "$IMGS1\n$IMGS2" | sort -u ) ; do
			let ALL_IMAGES+=1
			if [ ! -f $TMPDIR/b1/targets/$target/$subtarget/$image -o ! -f $TMPDIR/b2/targets/$target/$subtarget/$image ] ; then
				echo "         <tr><td><img src=\"/userContent/static/weather-storm.png\" alt=\"ftbfs icon\" /> $image (${SIZE}) failed to build.</td></tr>" >> $DBD_HTML
				rm -f $BASE/lede/dbd/targets/$target/$subtarget/$image.html # cleanup from previous (unreproducible) tests - if needed
				continue
			fi

			if [ "$(sha256sum "$TMPDIR/b1/targets/$target/$subtarget/$image" "$TMPDIR/b2/targets/$target/$subtarget/$image" \
				| cut -f 1 -d ' ' | uniq -c  | wc -l)" != "1" ] ; then
				call_diffoscope targets/$target/$subtarget $image
			else
				echo "$(date -u) - targets/$target/$subtarget/$image is reproducible, yip!"
			fi
			get_filesize $image
			if [ -f $TMPDIR/targets/$target/$subtarget/$image.html ] ; then
				mkdir -p $BASE/lede/dbd/targets/$target/$subtarget
				mv $TMPDIR/targets/$target/$subtarget/$image.html $BASE/lede/dbd/targets/$target/$subtarget/$image.html
				echo "         <tr><td><a href=\"dbd/targets/$target/$subtarget/$image.html\"><img src=\"/userContent/static/weather-showers-scattered.png\" alt=\"unreproducible icon\" /> $image</a> (${SIZE}) is unreproducible.</td></tr>" >> $DBD_HTML
			else
				SHASUM=$(sha256sum $image|cut -d " " -f1)
				echo "         <tr><td><img src=\"/userContent/static/weather-clear.png\" alt=\"reproducible icon\" /> $image ($SHASUM, $SIZE) is reproducible.</td></tr>" >> $DBD_HTML
				let GOOD_IMAGES+=1
				rm -f $BASE/lede/dbd/targets/$target/$subtarget/$image.html # cleanup from previous (unreproducible) tests - if needed
			fi
		done
		cd ..
		echo "       </table>" >> $DBD_HTML
	done
	cd ..
done
GOOD_PERCENT_IMAGES=$(echo "scale=1 ; ($GOOD_IMAGES*100/$ALL_IMAGES)" | bc)
# run diffoscope on the packages
GOOD_PACKAGES=0
ALL_PACKAGES=0
cd $TMPDIR/b1
for i in * ; do
	cd $i

	# search packages in both paths to find non-existing ones
	PKGS1=$(find * -type f -name "*.ipk" | sort -u )
	pushd $TMPDIR/b2/$i
	PKGS2=$(find * -type f -name "*.ipk" | sort -u )
	popd

	for j in $(printf "$PKGS1\n$PKGS2" | sort -u ) ; do
		let ALL_PACKAGES+=1
		if [ ! -f $TMPDIR/b1/$i/$j -o ! -f $TMPDIR/b2/$i/$j ] ; then
			echo "         <tr><td><img src=\"/userContent/static/weather-storm.png\" alt=\"ftbfs icon\" /> $j (${SIZE}) failed to build.</td></tr>" >> $DBD_BAD_PKGS_HTML
			rm -f $BASE/lede/dbd/$i/$j.html # cleanup from previous (unreproducible) tests - if needed
			continue
		fi

		if [ "$(sha256sum $TMPDIR/b1/$i/$j $TMPDIR/b2/$i/$j | cut -f 1 -d ' ' | uniq -c  | wc -l)" != "1" ] ; then
			call_diffoscope $i $j
		else
			echo "$(date -u) - $i/$j is reproducible, yip!"
		fi
		get_filesize $j
		if [ -f $TMPDIR/$i/$j.html ] ; then
			mkdir -p $BASE/lede/dbd/$i/$(dirname $j)
			mv $TMPDIR/$i/$j.html $BASE/lede/dbd/$i/$j.html
			echo "         <tr><td><a href=\"dbd/$i/$j.html\"><img src=\"/userContent/static/weather-showers-scattered.png\" alt=\"unreproducible icon\" /> $j</a> ($SIZE) is unreproducible.</td></tr>" >> $DBD_BAD_PKGS_HTML
		else
			SHASUM=$(sha256sum $j|cut -d " " -f1)
			echo "         <tr><td><img src=\"/userContent/static/weather-clear.png\" alt=\"reproducible icon\" /> $j ($SHASUM, $SIZE) is reproducible.</td></tr>" >> $DBD_GOOD_PKGS_HTML
			let GOOD_PACKAGES+=1
			rm -f $BASE/lede/dbd/$i/$j.html # cleanup from previous (unreproducible) tests - if needed
		fi
	done
	cd ..
done
echo "       <table><tr><th>Unreproducible and otherwise broken packages</th></tr>" >> $DBD_HTML
cat $DBD_BAD_PKGS_HTML >> $DBD_HTML
echo "       </table>" >> $DBD_HTML
echo "       <table><tr><th>Reproducible packages</th></tr>" >> $DBD_HTML
cat $DBD_GOOD_PKGS_HTML >> $DBD_HTML
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
cd $TMPDIR ; mkdir lede
PAGE=lede/lede_$LEDE_TARGET.html
cat > $PAGE <<- EOF
<!DOCTYPE html>
<html lang="en-US">
  <head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width">
    <title>Reproducible LEDE ?</title>
    <link rel="stylesheet" href="foundation.css"/>
    <link rel="stylesheet" href="font-awesome.css"/>
    <link rel="stylesheet" href="coderay.css"/>
    <link rel="stylesheet" href="asciidoctor.css"/>
    <link rel="stylesheet" href="lede.css"/>
  </head>
  <body>
    <div id="content">
        <pre>
EOF
cat $BANNER_HTML >> $PAGE
write_page "       </pre>"
write_page "     </div><div id=\"main-content\">"
write_page "       <h1>LEDE - <em>reproducible</em> wireless freedom$MAGIC_SIGN</h1>"
write_page_intro LEDE
write_page "       <p>$GOOD_IMAGES ($GOOD_PERCENT_IMAGES%) out of $ALL_IMAGES built images and $GOOD_PACKAGES ($GOOD_PERCENT_PACKAGES%) out of $ALL_PACKAGES built packages were reproducible in our test setup."
write_page "        These tests were last run on $DATE for version ${OPENWRT_VERSION} using ${DIFFOSCOPE}.</p>"
write_variation_table LEDE
cat $DBD_HTML >> $PAGE
write_page "     <table><tr><th>git commit built</th></tr><tr><td><code>"
cat $GIT_COMMIT >> $PAGE
write_page "     </code></td></tr></table>"
cat $TOOLCHAIN_HTML >> $PAGE
write_page "    </div>"
write_page_footer LEDE
publish_page
rm -f $DBD_HTML $DBD_GOOD_PKGS_HTML $DBD_BAD_PKGS_HTML $TOOLCHAIN_HTML $BANNER_HTML $GIT_COMMIT

# the end
calculate_build_duration
print_out_duration
irc_message reproducible-builds "$REPRODUCIBLE_URL/$PAGE has been updated. ($GOOD_PERCENT_IMAGES% images and $GOOD_PERCENT_PACKAGES% packages reproducible)"
echo "============================================================================="

# remove everything, we don't need it anymore...
master_cleanup_tmpdirs success
trap - INT TERM EXIT
