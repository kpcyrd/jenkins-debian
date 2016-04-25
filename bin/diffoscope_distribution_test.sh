#!/bin/bash

# Copyright 2014-2016 Holger Levsen <holger@layer-acht.org>
# released under the GPLv=2

DEBUG=false
. /srv/jenkins/bin/common-functions.sh
common_init "$@"

check_pypi() {
	TMPPYPI=$(mktemp -t diffoscope-distribution-XXXXXXXX)
	# the following two lines are a bit fragile…
	curl https://pypi.python.org/pypi/diffoscope/ -o $TMPPYPI
	DIFFOSCOPE_IN_PYPI=$(grep "<title>" $TMPPYPI | cut -d ">" -f2- | cut -d ":" -f1 |cut -d " " -f2)
	rm -f $TMPPYPI > /dev/null
	echo
	echo
	if [ "$DIFFOSCOPE_IN_DEBIAN" = "$DIFFOSCOPE_IN_PYPI" ] ; then
		echo "Yay. diffoscope in Debian has the same version as on PyPI: $DIFFOSCOPE_IN_DEBIAN"
	elif dpkg --compare-versions "$DIFFOSCOPE_IN_DEBIAN" gt "$DIFFOSCOPE_IN_PYPI" ; then
		echo "Fail: diffoscope in Debian: $DIFFOSCOPE_IN_DEBIAN"
		echo "Fail: diffoscope in PyPI:   $DIFFOSCOPE_IN_PYPI"
		exit 1
	else
		echo "diffoscope in Debian: $DIFFOSCOPE_IN_DEBIAN"
		echo "diffoscope in PyPI:   $DIFFOSCOPE_IN_PYPI"
		echo
		echo "Failure is the default action…"
		exit 1
	fi
}

#
# main
#
DIFFOSCOPE_IN_DEBIAN=$(rmadison diffoscope|egrep '(unstable|sid)'| awk '{print $3}' || true)

case $1 in
	pypi)	
		DISTRIBUTION=$1
		check_pypi
		;;
	*)
		echo "Unsupported distribution."
		exit 1
		;;
esac



