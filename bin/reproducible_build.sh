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

COUNT_TOTAL=0
COUNT_GOOD=0
COUNT_BAD=0
for PACKAGE in "$@" ; do
	let "COUNT_TOTAL=COUNT_TOTAL+1"
	rm b1 b2 -rf
	apt-get source --download-only ${PACKAGE}
	sudo pbuilder --build --basetgz /var/cache/pbuilder/base-reproducible.tgz ${PACKAGE}_*.dsc
	mkdir b1 b2
	dcmd cp /var/cache/pbuilder/result/${PACKAGE}_*.changes b1
	sudo dcmd rm /var/cache/pbuilder/result/${PACKAGE}_*.changes
	sudo pbuilder --build --basetgz /var/cache/pbuilder/base-reproducible.tgz ${PACKAGE}_*.dsc
	dcmd cp /var/cache/pbuilder/result/${PACKAGE}_*.changes b2
	sudo dcmd rm /var/cache/pbuilder/result/${PACKAGE}_*.changes
	cat b1/${PACKAGE}_*.changes

	TMPFILE=$(mktemp)
	./misc.git/diffp b1/*.changes b2/*.changes | tee ${TMPFILE}
	if $(grep -qv '^\*\*\*\*\*' ${TMPFILE}) ; then
		figlet ${PACKAGE}
		echo
		echo "${PACKAGE} build successfull."
		let "COUNT_GOOD=COUNT_GOOD+1"
	else
		echo "Warning: ${PACKAGE} failed to build reproducible."
		let "COUNT_BAD=COUNT_BAD+1"
	fi

	rm b1 b2 ${TMPFILE} -rf
done

echo
echo "$COUNT_TOTAL packages attempted to build in total."
echo "$COUNT_GOOD packages successfully built reproducible."
echo "$COUNT_BAD packages failed to built reproducible."
echo
echo "The full list of packages: $@"
