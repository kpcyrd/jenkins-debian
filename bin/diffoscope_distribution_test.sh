#!/bin/bash

# Copyright 2014-2016 Holger Levsen <holger@layer-acht.org>
# released under the GPLv=2

DEBUG=false
. /srv/jenkins/bin/common-functions.sh
common_init "$@"

# common code (used for irc_message)
. /srv/jenkins/bin/reproducible_common.sh

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
		irc_message debian-reproducible "It seems diffoscope $DIFFOSCOPE_IN_DEBIAN is not available on PyPI, which only has $DIFFOSCOPE_IN_PYPI."
		exit 1
	else
		echo "diffoscope in Debian: $DIFFOSCOPE_IN_DEBIAN"
		echo "diffoscope in PyPI:   $DIFFOSCOPE_IN_PYPI"
		echo
		echo "Failure is the default action…"
		exit 1
	fi
}

check_whohas() {
	# the following is "broken" (but good enough for now)
	# as sort doesn't do proper version comparison
	DIFFOSCOPE_IN_WHOHAS=$(whohas -d $DISTRIBUTION diffoscope | awk '{print $3}' | sort -u | tail -1)
	echo
	echo
	if [ "$DIFFOSCOPE_IN_DEBIAN" = "$DIFFOSCOPE_IN_WHOHAS" ] ; then
		echo "Yay. diffoscope in Debian has the same version as $DISTRIBUTION has: $DIFFOSCOPE_IN_DEBIAN"
	elif dpkg --compare-versions "$DIFFOSCOPE_IN_DEBIAN" gt "$DIFFOSCOPE_IN_WHOHAS" ; then
		echo "Fail: diffoscope in Debian: $DIFFOSCOPE_IN_DEBIAN"
		echo "Fail: diffoscope in $DISTRIBUTION: $DIFFOSCOPE_IN_WHOHAS"
		exit 1
	else
		# FIXME: archlinux package version will be greater than Debian: 52-1 vs 52
		echo "diffoscope in Debian: $DIFFOSCOPE_IN_DEBIAN"
		echo "diffoscope in $DISTRIBUTION: $DIFFOSCOPE_IN_WHOHAS"
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
	PyPI)	check_pypi
		;;
	FreeBSD|NetBSD|MacPorts)
		DISTRIBUTION=$1
		check_whohas
		# missing tests: Arch, Fedora, openSUSE, maybe OpenBSD, Guix…
		;;
	*)
		echo "Unsupported distribution."
		exit 1
		;;
esac

