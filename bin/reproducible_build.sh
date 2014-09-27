#!/bin/bash

# Copyright 2014 Holger Levsen <holger@layer-acht.org>
# released under the GPLv=2

. /srv/jenkins/bin/common-functions.sh
common_init "$@"

if [ -d misc.git ] ; then
	cd misc.git
	git pull
	cd ..
else
	git clone git://git.debian.org/git/reproducible/misc.git misc.git
fi

set +x
echo
echo "=============================================================="
echo "The following source packages will be build: $@"
echo "=============================================================="
echo
set -x
# this needs sid entries in sources.list:
grep deb-src /etc/apt/sources.list | grep sid
sudo apt-get update

# if $1 is an integer, build $1 random packages
if [[ $1 =~ ^-?[0-9]+$ ]] ; then
	TMPFILE=$(mktemp)
	curl http://ftp.de.debian.org/debian/dists/sid/main/source/Sources.xz > $TMPFILE
	AMOUNT=$1
	PACKAGES=$(xzcat $TMPFILE | grep "^Package" | cut -d " " -f2 | sort -R | head -$AMOUNT | xargs echo)
	rm $TMPFILE
else
	PACKAGES="$@"
fi

COUNT_TOTAL=0
COUNT_GOOD=0
COUNT_BAD=0
GOOD=""
BAD=""
SOURCELESS=""
for SRCPACKAGE in $PACKAGES ; do
	let "COUNT_TOTAL=COUNT_TOTAL+1"
	rm b1 b2 -rf
	set +e
	apt-get source --download-only ${SRCPACKAGE}
	RESULT=$?
	if [ $RESULT != 0 ] ; then
		SOURCELESS="${SOURCELESS} ${SRCPACKAGE}"
		echo "Warning: ${SRCPACKAGE} is not a source package, or was removed or renamed. Please investigate."
	else
		sudo DEB_BUILD_OPTIONS="parallel=4 nocheck" pbuilder --build --basetgz /var/cache/pbuilder/base-reproducible.tgz --distribution sid ${SRCPACKAGE}_*.dsc
		RESULT=$?
		if [ $RESULT = 0 ] ; then
			mkdir b1 b2
			dcmd cp /var/cache/pbuilder/result/${SRCPACKAGE}_*.changes b1
			sudo dcmd rm /var/cache/pbuilder/result/${SRCPACKAGE}_*.changes
			sudo DEB_BUILD_OPTIONS="parallel=4 nocheck" pbuilder --build --basetgz /var/cache/pbuilder/base-reproducible.tgz --distribution sid ${SRCPACKAGE}_*.dsc
			dcmd cp /var/cache/pbuilder/result/${SRCPACKAGE}_*.changes b2
			sudo dcmd rm /var/cache/pbuilder/result/${SRCPACKAGE}_*.changes
			set -e
			cat b1/${SRCPACKAGE}_*.changes
			mkdir -p results/_success
			LOGFILE=$(ls ${SRCPACKAGE}_*.dsc)
			LOGFILE=$(echo ${LOGFILE%.dsc}.diffp)
			./misc.git/diffp b1/${SRCPACKAGE}_*.changes b2/${SRCPACKAGE}_*.changes | tee ./results/${LOGFILE}
			if ! $(grep -qv '^\*\*\*\*\*' ./results/${LOGFILE}) ; then
				mv ./results/${LOGFILE} ./results/_success/
				figlet ${SRCPACKAGE}
				echo
				echo "${SRCPACKAGE} built successfully and reproducibly."
				let "COUNT_GOOD=COUNT_GOOD+1"
				GOOD="${SRCPACKAGE} ${GOOD}"
				touch results/___.dummy.log # not having any bad logs is not a reason for failure
			else
				echo "Warning: ${SRCPACKAGE} failed to build reproducibly."
				let "COUNT_BAD=COUNT_BAD+1"
				BAD="${SRCPACKAGE} ${BAD}"
				rm -f results/dummy.log 2>/dev/null # just cleanup
			fi
			rm b1 b2 -rf
		fi
		dcmd rm ${SRCPACKAGE}_*.dsc
	fi

	set +x
	echo "=============================================================="
	echo "$COUNT_TOTAL of ${#@} done."
	echo "=============================================================="
	set -x
done

set +x
echo
echo
echo "$COUNT_TOTAL packages attempted to build in total."
echo "$COUNT_GOOD packages successfully built reproducibly: ${GOOD}"
echo "$COUNT_BAD packages failed to built reproducibly: ${BAD}"
echo "The following source packages doesn't exist in sid: $SOURCELESS"
