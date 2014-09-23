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

for PACKAGE in "$@" ; do
	rm b1 b2 -rf
	apt-get source --download-only ${PACKAGE}
	sudo pbuilder --build --basetgz /var/cache/pbuilder/base-reproducible.tgz ${PACKAGE}_*.dsc
	mkdir b1 b2
	dcmd cp /var/cache/pbuilder/result/${PACKAGE}_*.changes b1
	sudo dcmd rm /var/cache/pbuilder/result/${PACKAGE}_*.changes
	sudo pbuilder --build --basetgz /var/cache/pbuilder/base-reproducible.tgz ${PACKAGE}_*.dsc
	dcmd cp /var/cache/pbuilder/result/${PACKAGE}_*.changes b2
	sudo dcmd rm /var/cache/pbuilder/result/${PACKAGE}_*.changes

	./misc.git/diffp b1/*.changes b2/*.changes

	rm b1 b2 -rf
done
