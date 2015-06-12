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

call_debbindiff() {
	local TMPLOG=(mktemp --tmpdir=$TMPDIR)
	local msg=""
	set +e
	( timeout $TIMEOUT schroot \
		--directory $TMPDIR \
		-c source:jenkins-reproducible-${DBDSUITE}-debbindiff \
		debbindiff -- \
			--html $TMPDIR/$1.html \
			$TMPDIR/b1/$1/coreboot.rom \
			$TMPDIR/b2/$1/coreboot.rom 2>&1 \
	) 2>&1 >> $TMPLOG
	RESULT=$?
	if ! "$DEBUG" ; then set +x ; fi
	set -e
	cat $TMPLOG # print dbd output
	rm -f $TMPLOG
	case $RESULT in
		0)	echo "$(date -u) - $1/coreboot.rom is reproducible, yay!"
			;;
		1)
			echo "$(date -u) - $DBDVERSION found issues, please investigate $1/coreboot.rom"
			;;
		2)
			msg="$(date -u) - $DBDVERSION had trouble comparing the two builds. Please investigate $1/coreboot.rom"
			;;
		124)
			if [ ! -s $TMPDIR/$1.html ] ; then
				msg="$(date -u) - $DBDVERSION produced no output for $1/coreboot.rom and was killed after running into timeout after ${TIMEOUT}..."
			else
				msg="$DBDVERSION was killed after running into timeout after $TIMEOUT, but there is still $TMPDIR/$1.html"
			fi
			;;
		*)
			msg="$(date -u) - Something weird happened when running $DBDVERSION on $1/coreboot.rom (which exited with $RESULT) and I don't know how to handle it."
			;;
	esac
	if [ ! -z $msg ] ; then
		echo $msg | tee -a $TMPDIR/$1.html
	fi
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
echo "$(date -u) - Cloning the coreboot git repository with submodules now."
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
echo "$(date -u) - Building cross compilers for ${ARCHS} now."
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
TOOLCHAIN_HTML=$(mktemp)
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
echo "$(date -u) - Building coreboot ${COREBOOT_VERSION} images now - first build run."
echo "============================================================================="
export TZ="/usr/share/zoneinfo/Etc/GMT+12"
# prevent failing using more than one CPU
sed -i 's#MAKE=$i#MAKE=make#' util/abuild/abuild
# use all cores for first build
sed -i "s#cpus=1#cpus=$NUM_CPU#" util/abuild/abuild
sed -i 's#USE_XARGS=1#USE_XARGS=0#g' util/abuild/abuild
# actually build everything
ionice -c 3 nice \
	bash util/abuild/abuild --payloads none || true # don't fail the full job just because some targets fail

# save results in b1
save_coreboot_results b1

echo "============================================================================="
echo "$(date -u) - Building coreboot images now - second build run."
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
	bash util/abuild/abuild --payloads none || true # don't fail the full job just because some targets fail

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

# run debbindiff on the results
TIMEOUT="30m"
DBDSUITE="unstable"
DBDVERSION="$(schroot --directory /tmp -c source:jenkins-reproducible-${DBDSUITE}-debbindiff debbindiff -- --version 2>&1)"
echo "============================================================================="
echo "$(date -u) - Running $DBDVERSION on coreboot images now"
echo "============================================================================="
ROMS_HTML=$(mktemp)
echo "       <ul>" > $ROMS_HTML
BAD_ROMS=0
GOOD_ROMS=0
ALL_ROMS=0
create_results_dirs
cd $TMPDIR/b1
for i in $(ls -1d *| sort -u) ; do
	let ALL_ROMS+=1
	if [ -f $i/coreboot.rom ] ; then
		call_debbindiff $i
		SIZE="$(du -h -b $i/coreboot.rom | cut -f1)"
		SIZE="$(echo $SIZE/1024|bc)"
		if [ -f $TMPDIR/$i.html ] ; then
			mv $TMPDIR/$i.html $BASE/coreboot/dbd/$i.html
			echo "         <li><a href=\"dbd/$i.html\"><img src=\"/userContent/static/weather-showers-scattered.png\" alt=\"unreproducible icon\" /> $i</a> (${SIZE}K) is unreproducible.</li>" >> $ROMS_HTML
		else
			SHASUM=$(sha256sum $i/coreboot.rom|cut -d " " -f1)
			echo "         <li><img src=\"/userContent/static/weather-clear.png\" alt=\"reproducible icon\" /> $i ($SHASUM, ${SIZE}K) is reproducible.</li>" >> $ROMS_HTML
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
    <title>coreboot</title>
    <link rel='stylesheet' id='twentyfourteen-style-css'  href='landing_style.css?ver=4.0' type='text/css' media='all' />
  </head>
  <body>
    <div class="content">
      <div class="page-content">
        <p>&nbsp;</p>
        <p><center><img src="coreboot.png" width="300" class="alignnone size-medium wp-image-6" alt="coreboot" height="231" /><br />
        <blockquote>
	  <br />
          <strong>coreboot&trade;</strong>: fast, flexible <em>and reproducible</em> Open Source firmware?
        </blockquote>
       </center></p>
EOF
write_page "       <h1>Reproducible Coreboot</h1>"
write_page "       <p><em>Reproducible builds</em> enable anyone to reproduce bit by bit identical binary packages from a given source, so that anyone can verify that a given binary derived from the source it was said to be derived. There is a lot more information about <a href=\"https://wiki.debian.org/ReproducibleBuilds\">reproducible builds on the Debian wiki</a> and on <a href=\"https://reproducible.debian.net\">https://reproducible.debian.net</a>. The wiki has a lot more information, eg. why this is useful, what common issues exist and which workarounds and solutions are known.<br />"
write_page "        <em>Reproducible Coreboot</em> is an effort to apply this to coreboot. Thus each coreboot.rom is build twice (without payloads), with a few varitations added and then those two ROMs are compared using <a href=\"https://tracker.debian.org/debbindiff\">debbindiff</a>. Please note that the toolchain is not varied at all as the rebuild happens on exactly the same system. More variations are expected to be seen in the wild.</p>"
write_page "       <p>There is a monthly run <a href=\"https://jenkins.debian.net/view/reproducible/job/reproducible_coreboot/\">jenkins job</a> to test the <code>master</code> branch of <a href=\"https://review.coreboot.org/p/coreboot.git\">coreboot.git</a>. Currently this job is triggered more often though, because this is still under development and brand new. The jenkins job is simply running <a href=\"http://anonscm.debian.org/cgit/qa/jenkins.debian.net.git/tree/bin/reproducible_coreboot.sh\">reproducible_coreboot.sh</a> in a Debian environemnt and this script is solely responsible for creating this page. Feel invited to join <code>#debian-reproducible</code> (on irc.oftc.net) to request job runs whenever sensible. Patches and other <a href=\"mailto:reproducible-builds@lists.alioth.debian.org\">feedback</a> are very much appreciated!</p>"
write_page "       <p>$GOOD_ROMS ($GOOD_PERCENT%) out of $ALL_ROMS built coreboot images were reproducible in our test setup, while $BAD_ROMS ($BAD_PERCENT%) failed to build from source."
write_page "        These tests were last run on $DATE for version ${COREBOOT_VERSION}.</p>"
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
