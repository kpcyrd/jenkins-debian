#!/bin/bash

# Copyright 2014 Holger Levsen <holger@layer-acht.org>
# released under the GPLv=2

. /srv/jenkins/bin/common-functions.sh
common_init "$@"

PACKAGE=$1
apt-get source --download-only ${PACKAGE}
sudo pbuilder --build --basetgz /var/cache/pbuilder/base-reproducible.tgz ${PACKAGE}_*.dsc
mkdir b1 b2
dcmd cp /var/cache/pbuilder/result/${PACKAGE}_*.changes b1
sudo dcmd rm /var/cache/pbuilder/result/${PACKAGE}_*.changes
sudo pbuilder --build --basetgz /var/cache/pbuilder/base-reproducible.tgz ${PACKAGE}_*.dsc
dcmd cp /var/cache/pbuilder/result/${PACKAGE}_*.changes b2
sudo dcmd rm /var/cache/pbuilder/result/${PACKAGE}_*.changes

