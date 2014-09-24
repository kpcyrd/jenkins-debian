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

COUNT_TOTAL=0
COUNT_GOOD=0
COUNT_BAD=0
GOOD=""
BAD=""
SOURCELESS=""
for SRCPACKAGE in "$@" ; do
	let "COUNT_TOTAL=COUNT_TOTAL+1"
	rm b1 b2 -rf
	set +e
	apt-get source --download-only ${SRCPACKAGE}
	RESULT=$?
	if [ $RESULT != 0 ] ; then
		SOURCELESS="${SOURCELESS} ${SRCPACKAGE}"
		echo "Warning: ${SRCPACKAGE} is not a source package, or was removed or renamed. Please investigate."
	else
		sudo pbuilder --build --basetgz /var/cache/pbuilder/base-reproducible.tgz ${SRCPACKAGE}_*.dsc
		RESULT=$?
		if [ $RESULT = 0 ] ; then
			mkdir b1 b2
			dcmd cp /var/cache/pbuilder/result/${SRCPACKAGE}_*.changes b1
			sudo dcmd rm /var/cache/pbuilder/result/${SRCPACKAGE}_*.changes
			sudo pbuilder --build --basetgz /var/cache/pbuilder/base-reproducible.tgz ${SRCPACKAGE}_*.dsc
			dcmd cp /var/cache/pbuilder/result/${SRCPACKAGE}_*.changes b2
			sudo dcmd rm /var/cache/pbuilder/result/${SRCPACKAGE}_*.changes
			set -e
			cat b1/${SRCPACKAGE}_*.changes
			TMPFILE=$(mktemp)
			./misc.git/diffp b1/${SRCPACKAGE}_*.changes b2/${SRCPACKAGE}_*.changes | tee ${TMPFILE}
			if ! $(grep -qv '^\*\*\*\*\*' ${TMPFILE}) ; then
				figlet ${SRCPACKAGE}
				echo
				echo "${SRCPACKAGE} build successfull."
				let "COUNT_GOOD=COUNT_GOOD+1"
				GOOD="${SRCPACKAGE} ${GOOD}"
			else
				echo "Warning: ${SRCPACKAGE} failed to build reproducible."
				let "COUNT_BAD=COUNT_BAD+1"
				GOOD="${SRCPACKAGE} ${BAD}"
			fi
			rm b1 b2 ${TMPFILE} -rf
		fi
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
echo "$COUNT_GOOD packages successfully built reproducible: ${GOOD}"
echo "$COUNT_BAD packages failed to built reproducible: ${BAD}"
echo "The following source packages doesn't exist in sid: $SOURCELESS"
