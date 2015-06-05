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

# support for different architectures (we start with i386 only)
ARCHS="i386"

cleanup_all() {
       rm -r $TMPDIR
}

create_results_dirs() {
	mkdir -p $BASE/coreboot/dbd
}

calculate_build_duration() {
	END=$(date +'%s')
	DURATION=$(( $END - $START ))
}

print_out_duration() {
	local HOUR=$(echo "$DURATION/3600"|bc)
	local MIN=$(echo "($DURATION-$HOUR*3600)/60"|bc)
	local SEC=$(echo "$DURATION-$HOUR*3600-$MIN*60"|bc)
	echo "$(date) - total duration: ${HOUR}h ${MIN}m ${SEC}s."
}

call_debbindiff() {
	local TMPLOG=(mktemp --tmpdir=$TMPDIR)
	echo
	set +e
	set -x
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
		0)	echo "$1/coreboot.rom is reproducible, yay!"
			;;
		1)
			echo "$DBDVERSION found issues, please investigate $1/coreboot.rom"
			;;
		2)
			echo "$DBDVERSION had trouble comparing the two builds. Please investigate $1/coreboot.rom"
			;;
		124)
			if [ ! -s $TMPDIR/$1.html ] ; then
				echo "$(date) - $DBDVERSION produced no output and was killed after running into timeout after ${TIMEOUT}..."
			else
				local msg="$DBDVERSION was killed after running into timeout after $TIMEOUT"
				msg="$msg, but there is still $TMPDIR/$1.html"
			fi
			echo $msg
			;;
		*)
			echo "Something weird happened when running $DBDVERSION (which exited with $RESULT) and I don't know how to handle it"
			;;
	esac
}

build_rebuild() {
	FTBFS=1
	local TMPCFG=$(mktemp -t pbuilderrc_XXXX --tmpdir=$TMPDIR)
	local NUM_CPU=$(cat /proc/cpuinfo |grep ^processor|wc -l)
	set -x
	printf "BUILDUSERID=1111\nBUILDUSERNAME=pbuilder1\n" > $TMPCFG
	( timeout -k 12h 12h nice ionice -c 3 sudo \
	  DEB_BUILD_OPTIONS="parallel=$NUM_CPU" \
	  TZ="/usr/share/zoneinfo/Etc/GMT+12" \
	  pbuilder --build \
		--configfile $TMPCFG \
		--debbuildopts "-b" \
		--basetgz /var/cache/pbuilder/$SUITE-reproducible-base.tgz \
		--buildresult b1 \
		${SRCPACKAGE}_*.dsc \
	) 2>&1 
	if ! "$DEBUG" ; then set +x ; fi
	if [ -f b1/${SRCPACKAGE}_${EVERSION}_${ARCH}.changes ] ; then
		# the first build did not FTBFS, try rebuild it.
		echo "============================================================================="
		echo "Re-building ${SRCPACKAGE}/${VERSION} in ${SUITE} on ${ARCH} now."
		echo "============================================================================="
		set -x
		printf "BUILDUSERID=2222\nBUILDUSERNAME=pbuilder2\n" > $TMPCFG
		( timeout -k 12h 12h nice ionice -c 3 sudo \
		  DEB_BUILD_OPTIONS="parallel=$(echo $NUM_CPU-1|bc)" \
		  TZ="/usr/share/zoneinfo/Etc/GMT-14" \
		  LANG="fr_CH.UTF-8" \
		  LC_ALL="fr_CH.UTF-8" \
		  /usr/bin/linux64 --uname-2.6 \
			/usr/bin/unshare --uts -- \
				/usr/sbin/pbuilder --build \
					--configfile $TMPCFG \
					--hookdir /etc/pbuilder/rebuild-hooks \
					--debbuildopts "-b" \
					--basetgz /var/cache/pbuilder/$SUITE-reproducible-base.tgz \
					--buildresult b2 \
					${SRCPACKAGE}_${EVERSION}.dsc
		) 2>&1
		if ! "$DEBUG" ; then set +x ; fi
		if [ -f b2/${SRCPACKAGE}_${EVERSION}_${ARCH}.changes ] ; then
			# both builds were fine, i.e., they did not FTBFS.
			FTBFS=0
			cat b1/${SRCPACKAGE}_${EVERSION}_${ARCH}.changes
		else
			echo "The second build failed, even though the first build was successful."
		fi
	fi
	rm $TMPCFG
	if [ $FTBFS -eq 1 ] ; then handle_ftbfs ; fi
}


#
# below is what controls the world
#

TMPDIR=$(mktemp --tmpdir=/srv/reproducible-results -d)  # where everything actually happens
trap cleanup_all INT TERM EXIT
cd $TMPDIR

DATE=$(date +'%Y-%m-%d %H:%M')
START=$(date +'%s')
mkdir b1 b2

echo "============================================================================="
echo "$(date) - Cloning the coreboot git repository with submodules now."
echo "============================================================================="
git clone --recursive http://review.coreboot.org/p/coreboot.git
cd coreboot
COREBOOT="$(git log -1 | head -3)"

echo "============================================================================="
echo "$(date) - Building cross compilers for ${ARCHS} now."
echo "============================================================================="
for ARCH in ${ARCHS} ; do 
	make crossgcc-$ARCH
done

echo "============================================================================="
echo "$(date) - Building coreboot images now - first build run."
echo "============================================================================="
export TZ="/usr/share/zoneinfo/Etc/GMT+12"
bash utils/abuild/abuild

cd coreboot-builds
for i in * ; do
	if [ -f $i/coreboot.rom ] ; then
		mkdir $TMPDIR/b1/$i
		cp -p $i/coreboot.rom $TMPDIR/b1/$i/
	fi
done
cd ..
rm coreboot-builds -rf

echo "============================================================================="
echo "$(date) - Building coreboot images now - second build run."
echo "============================================================================="
export TZ="/usr/share/zoneinfo/Etc/GMT-14"
export LANG="fr_CH.UTF-8"
export LC_ALL="fr_CH.UTF-8"
bash utils/abuild/abuild

export LANG="en_GB.UTF-8"
unset LC_ALL
export TZ="/usr/share/zoneinfo/UTC"

cd coreboot-builds
for i in * ; do
	if [ -f $i/coreboot.rom ] ; then
		mkdir $TMPDIR/b2/$i
		cp -p $i/coreboot.rom $TMPDIR/b2/$i/
	fi
done
cd ..
rm coreboot-builds -rf

# remove coreboot tree, we don't need it anymore...
cd ..
rm coreboot -rf

TIMEOUT="30m"
DBDSUITE="unstable"
DBDVERSION="$(schroot --directory /tmp -c source:jenkins-reproducible-${DBDSUITE}-debbindiff debbindiff -- --version 2>&1)"
echo "============================================================================="
echo "$(date) - Running $DBDVERSION on coreboot images now"
echo "============================================================================="

PAGE=$BASE/coreboot/coreboot.html
echo "<html><head></head><body><h1>Reproducible Coreboot</h2><p>This is work in progress - only TZ, LAND and LC_CTYPE variations yet and no fancy html.</p><pre>" > $PAGE
echo -n $COREBOOT >> $PAGE
echo "</pre><ul>" >> $PAGE

cd b1
for i in * ; do
	call_debbindiff $i
	if [ -f $TMPDIR/$i.html ] ; then
		mv $TMPDIR/$i.html $BASE/coreboot/dbd/$i.html
		echo "<li><a href=\"dbd/$i.html\">$i debbindiff output</li>" >> $PAGE
	else
		echo "<li>$i had no debbindiff output - it's probably reproducible :)</li>" >> $PAGE
	fi
done
echo "</ul></body></html>" >> $PAGE
cd ..
echo "Enjoy $REPRODUCIBLE_URL/coreboot.html"

#build_rebuild  # defines FTBFS
#if [ $FTBFS -eq 0 ] ; then
#	call_debbindiff  # defines DBDVERSION, update_db_and_html defines STATUS
#fi

calculate_build_duration
print_out_duration

cd ..
cleanup_all
trap - INT TERM EXIT

