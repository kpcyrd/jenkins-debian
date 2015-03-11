#!/bin/bash

# Copyright 2014 Holger Levsen <holger@layer-acht.org>
#         © 2015 Mattia Rizzolo <mattia@mapreri.org>
# released under the GPLv=2

DEBUG=false
. /srv/jenkins/bin/common-functions.sh
common_init "$@"

# common code defining db access
. /srv/jenkins/bin/reproducible_common.sh

blacklist_packages() {
	DATE=$(date +'%Y-%m-%d %H:%M')
	TMPFILE=$(mktemp)
	for PKG in $PACKAGES ; do
		VERSION=$(sqlite3 -init $INIT ${PACKAGES_DB} "SELECT version FROM sources WHERE name='$PKG' AND suite='$SUITE';")
		PKGID=$(sqlite3 -init $INIT ${PACKAGES_DB} "SELECT id FROM sources WHERE name='$PKG' AND suite='$SUITE';")
		sqlite3 -init $INIT ${PACKAGES_DB} "REPLACE INTO results (package_id, version, status, build_date) VALUES ('$PKGID', '$VERSION', 'blacklisted', '$DATE');"
	done
}

check_candidates() {
	PACKAGES=""
	TOTAL=0
	for PKG in $CANDIDATES ; do
		RESULT=$(sqlite3 -init $INIT ${PACKAGES_DB} "SELECT name from sources WHERE name='$PKG' AND suite='$SUITE';")
		if [ ! -z "$RESULT" ] ; then
			PACKAGES="$PACKAGES $RESULT"
			let "TOTAL+=1"
		fi
	done
}



#
# main
#
set +x
SUITE="$1"
shift
CANDIDATES="$@"
check_candidates
PACKAGES=$(echo $PACKAGES)
MESSAGE="$TOTAL package(s) blacklisted in $SUITE: ${PACKAGES}"
if [ $TOTAL -lt 1 ] ; then
	exit 1
fi

# finally
blacklist_packages
gen_packages_html $SUITE $PACKAGES
echo
echo "$MESSAGE"
kgb-client --conf /srv/jenkins/kgb/debian-reproducible.conf --relay-msg "$MESSAGE"
echo
echo "============================================================================="
echo "The following $TOTAL source packages from $SUITE have been blacklisted: $PACKAGES"
echo "============================================================================="
echo
echo "Probably edit notes.git/packages.yml now and enter reasons for blacklisting there"
