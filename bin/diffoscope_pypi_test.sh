#!/bin/bash

# Copyright 2014-2016 Holger Levsen <holger@layer-acht.org>
# released under the GPLv=2

DEBUG=false
. /srv/jenkins/bin/common-functions.sh
common_init "$@"

cleanup_all() {
	rm $TMPPYPI
}

#
# main
#
TMPPYPI=$(mktemp -t diffoscope-pypi-XXXXXXXX)
trap cleanup_all INT TERM EXIT

DIFFOSCOPE_IN_DEBIAN=$(rmadison diffoscope|grep unstable| cut -d "|" -f2 || true)
curl https://pypi.python.org/pypi/diffoscope/ -o $TMPPYPI
DIFFOSCOPE_IN_PYPI=$(grep "<title>" $TMPPYPI | cut -d ">" -f2- | cut -d ":" -f1 |cut -d " " -f2)
echo
echo
if [ "$DIFFOSCOPE_IN_DEBIAN" = "$DIFFOSCOPE_IN_PYPI" ] ; then
	echo "Yay. diffoscope in Debian has the same version as on PyPI."
elif dpkg --compare-versions "$DIFFOSCOPE_IN_DEBIAN" gt "$DIFFOSCOPE_IN_PYPI" ; then
	echo "Fail: diffoscope in Debian: $DIFFOSCOPE_IN_DEBIAN"
	echo "Fail: diffoscope in PyPI:   $DIFFOSCOPE_IN_PYPI"
	exit 1
fi

# the end
cleanup_all
trap - INT TERM EXIT
