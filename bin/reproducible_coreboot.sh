#!/bin/bash

# Copyright 2014-2015 Holger Levsen <holger@layer-acht.org>
# released under the GPLv=2

DEBUG=false
. /srv/jenkins/bin/common-functions.sh
common_init "$@"

# common code defining db access
. /srv/jenkins/bin/reproducible_common.sh

set -e

# build for different architectures
ARCHS="i386-elf x86_64-elf armv7a-eabi aarch64-elf mipsel-elf riscv-elf"

cleanup_tmpdirs() {
	cd
	rm -r $TMPDIR
	rm -r $TMPBUILDDIR
}

create_results_dirs() {
	mkdir -p $BASE/coreboot/dbd
}

save_coreboot_results(){
	RUN=$1
	cd coreboot-builds
	for i in * ; do
		if [ -f $i/coreboot.rom ] ; then
			mkdir -p $TMPDIR/$RUN/$i
			cp -p $i/coreboot.rom $TMPDIR/$RUN/$i/
		fi
	done
	cd ..
	rm coreboot-builds -r
}

#
# main
#
TMPBUILDDIR=$(mktemp --tmpdir=/srv/workspace/chroots/ -d -t coreboot-XXXXXXXX)  # used to build on tmpfs
TMPDIR=$(mktemp --tmpdir=/srv/reproducible-results -d)  # accessable in schroots, used to compare results
DATE=$(date -u +'%Y-%m-%d')
START=$(date +'%s')
trap cleanup_tmpdirs INT TERM EXIT

cd $TMPBUILDDIR
echo "============================================================================="
echo "$(date -u) - Cloning the coreboot git repository with submodules."
echo "============================================================================="
git clone --recursive http://review.coreboot.org/p/coreboot.git
cd coreboot
# still required because coreboot moved submodules and to take care of old git versions
git submodule update --init --checkout 3rdparty/blobs
COREBOOT="$(git log -1)"
COREBOOT_VERSION=$(git describe)
echo "This is coreboot $COREBOOT_VERSION."
echo
git log -1

echo "============================================================================="
echo "$(date -u) - Building cross compilers for ${ARCHS}."
GOT_XTOOLCHAIN=false
#
# build the cross toolchains
#
set +e
for ARCH in ${ARCHS} ; do
	echo "============================================================================="
	echo "$(date -u) - Building cross compiler for ${ARCH}."
	# taken from util/crossgcc/Makefile:
	ionice -c 3 nice bash util/crossgcc/buildgcc -j $NUM_CPU -p $ARCH
	RESULT=$?
	if [ $RESULT -eq 0 ] ; then
		GOT_XTOOLCHAIN=true
	fi
done
set -e
if ! $GOT_XTOOLCHAIN ; then
	echo "Need at least one cross toolchain, aborting."
fi
#
# create html about toolchains used
#
TOOLCHAIN_HTML=$(mktemp --tmpdir=$TMPDIR)
echo "<table><tr><th>cross toolchain source</th><th>sha256sum</th></tr>" > $TOOLCHAIN_HTML
cd util/crossgcc/tarballs
for i in * ; do
	echo " <tr><td>$i</td><td>" >> $TOOLCHAIN_HTML
	sha256sum $i | cut -d " " -f1 >> $TOOLCHAIN_HTML
	echo " </td></tr>" >> $TOOLCHAIN_HTML
done
echo "</table>" >> $TOOLCHAIN_HTML
echo "<table><tr><th>Debian $(cat /etc/debian_version) package on $(dpkg --print-architecture)</th><th>installed version</th></tr>" >> $TOOLCHAIN_HTML
for i in gcc g++ make cmake flex bison iasl ; do
	echo " <tr><td>$i</td><td>" >> $TOOLCHAIN_HTML
	dpkg -s $i|grep '^Version'|cut -d " " -f2 >> $TOOLCHAIN_HTML
	echo " </td></tr>" >> $TOOLCHAIN_HTML
done
echo "</table>" >> $TOOLCHAIN_HTML
cd ../../..

echo "============================================================================="
echo "$(date -u) - Building coreboot ${COREBOOT_VERSION} images - first build run."
echo "============================================================================="
export TZ="/usr/share/zoneinfo/Etc/GMT+12"
# prevent failing using more than one CPU
sed -i 's#MAKE=$i#MAKE=make#' util/abuild/abuild
# use all cores for first build
sed -i "s#cpus=1#cpus=$NUM_CPU#" util/abuild/abuild
sed -i 's#USE_XARGS=1#USE_XARGS=0#g' util/abuild/abuild
# actually build everything
ionice -c 3 nice \
	bash util/abuild/abuild || true # don't fail the full job just because some targets fail
	#bash util/abuild/abuild --payloads none || true # don't fail the full job just because some targets fail

# save results in b1
save_coreboot_results b1

echo "============================================================================="
echo "$(date -u) - Building coreboot images - second build run."
echo "============================================================================="
export TZ="/usr/share/zoneinfo/Etc/GMT-14"
export LANG="fr_CH.UTF-8"
export LC_ALL="fr_CH.UTF-8"
export PATH="/usr/sbin:/usr/bin:/sbin:/bin:/usr/games:/i/capture/the/path"
export CAPTURE_ENVIRONMENT="I capture the environment"
umask 0002
# use allmost all cores for second build
NEW_NUM_CPU=$(echo $NUM_CPU-1|bc)
sed -i "s#cpus=$NUM_CPU#cpus=$NEW_NUM_CPU#" util/abuild/abuild
ionice -c 3 nice \
	linux64 --uname-2.6 \
	bash util/abuild/abuild || true # don't fail the full job just because some targets fail
	#bash util/abuild/abuild --payloads none || true # don't fail the full job just because some targets fail

# reset environment to default values again
export LANG="en_GB.UTF-8"
unset LC_ALL
export TZ="/usr/share/zoneinfo/UTC"
export PATH="/usr/sbin:/usr/bin:/sbin:/bin:/usr/games:"
umask 0022

# save results in b2
save_coreboot_results b2

# clean up builddir to save space on tmpfs
rm -r $TMPBUILDDIR/coreboot

# run diffoscope on the results
TIMEOUT="30m"
DBDSUITE="unstable"
DIFFOSCOPE="$(schroot --directory /tmp -c source:jenkins-reproducible-${DBDSUITE}-diffoscope diffoscope -- --version 2>&1)"
echo "============================================================================="
echo "$(date -u) - Running $DIFFOSCOPE on coreboot images."
echo "============================================================================="
ROMS_HTML=$(mktemp --tmpdir=$TMPDIR)
echo "       <ul>" > $ROMS_HTML
BAD_ROMS=0
GOOD_ROMS=0
ALL_ROMS=0
SIZE=""
create_results_dirs
cd $TMPDIR/b1
for i in $(ls -1d *| sort -u) ; do
	let ALL_ROMS+=1
	if [ -f $i/coreboot.rom ] ; then
		call_diffoscope $i coreboot.rom
		get_filesize $i/coreboot.rom
		if [ -f $TMPDIR/$i.html ] ; then
			mv $TMPDIR/$i.html $BASE/coreboot/dbd/$i.html
			echo "         <li><a href=\"dbd/$i.html\"><img src=\"/userContent/static/weather-showers-scattered.png\" alt=\"unreproducible icon\" /> $i</a> ($SIZE) is unreproducible.</li>" >> $ROMS_HTML
		else
			SHASUM=$(sha256sum $i/coreboot.rom|cut -d " " -f1)
			echo "         <li><img src=\"/userContent/static/weather-clear.png\" alt=\"reproducible icon\" /> $i ($SHASUM, $SIZE) is reproducible.</li>" >> $ROMS_HTML
			let GOOD_ROMS+=1
			rm -f $BASE/coreboot/dbd/$i.html # cleanup from previous (unreproducible) tests - if needed
		fi
	else
		echo "         <li><img src=\"/userContent/static/weather-storm.png\" alt=\"FTBFS icon\" /> $i <a href=\"${BUILD_URL}console\">failed to build</a> from source.</li>" >> $ROMS_HTML
		let BAD_ROMS+=1
	fi
done
echo "       </ul>" >> $ROMS_HTML
GOOD_PERCENT=$(echo "scale=1 ; ($GOOD_ROMS*100/$ALL_ROMS)" | bc)
BAD_PERCENT=$(echo "scale=1 ; ($BAD_ROMS*100/$ALL_ROMS)" | bc)
# are we there yet?
if [ "$GOOD_PERCENT" = "100.0" ] ; then
	MAGIC_SIGN="!"
else
	MAGIC_SIGN="?"
fi

#
#  finally create the webpage
#
cd $TMPDIR ; mkdir coreboot
PAGE=coreboot/coreboot.html
cat > $PAGE <<- EOF
<!DOCTYPE html>
<html lang="en-US">
  <head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width">
    <title>Reproducible coreboot</title>
    <link rel='stylesheet' id='twentyfourteen-style-css'  href='landing_style.css?ver=4.0' type='text/css' media='all' />
  </head>
  <body>
    <div class="content">
      <div class="page-content">
        <p>&nbsp;</p>
        <p><center><img src="coreboot.png" width="300" class="alignnone size-medium wp-image-6" alt="coreboot" height="231" /><br />
        <blockquote>
	  <br />
          <strong>coreboot&trade;</strong>: fast, flexible <em>and reproducible</em> Open Source firmware$MAGIC_SIGN
        </blockquote>
       </center></p>
EOF
write_page "       <h1>Reproducible Coreboot</h1>"
write_page_intro coreboot
write_page "       <p>$GOOD_ROMS ($GOOD_PERCENT%) out of $ALL_ROMS built coreboot images were reproducible in our test setup"
if [ "$GOOD_PERCENT" = "100.0" ] ; then
	write_page "!"
else
	write_page ", while $BAD_ROMS ($BAD_PERCENT%) failed to build from source."
fi
write_page "        These tests were last run on $DATE for version ${COREBOOT_VERSION} using ${DIFFOSCOPE}.</p>"
write_explaination_table coreboot
cat $ROMS_HTML >> $PAGE
write_page "     <p><pre>"
echo -n "$COREBOOT" >> $PAGE
write_page "     </pre></p>"
cat $TOOLCHAIN_HTML >> $PAGE
write_page "    </div></div>"
write_page_footer coreboot
publish_page
rm -f $ROMS_HTML $TOOLCHAIN_HTML

# the end
calculate_build_duration
print_out_duration
irc_message "$REPRODUCIBLE_URL/coreboot/ has been updated. ($GOOD_PERCENT% reproducible)"
echo "============================================================================="

# remove everything, we don't need it anymore...
cleanup_tmpdirs
trap - INT TERM EXIT
