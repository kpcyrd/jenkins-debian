#!/bin/bash

# Copyright 2014 Holger Levsen <holger@layer-acht.org>
# released under the GPLv=2

. /srv/jenkins/bin/common-functions.sh
common_init "$@"

# common code defining db access
. /srv/jenkins/bin/reproducible_common.sh

blacklist_packages() {
	DATE=$(date +'%Y-%m-%d %H:%M')
	TMPFILE=$(mktemp)
	for PKG in $PACKAGES ; do
		VERSION=$(sqlite3 -init $INIT ${PACKAGES_DB} "SELECT version from sources WHERE name = '$PKG';")
		sqlite3 -init $INIT ${PACKAGES_DB} "REPLACE INTO source_packages VALUES ('$PKG','$VERSION','blacklisted','$DATE');"
	done
	echo "============================================================================="
	echo "The following $TOTAL source packages have been (re-)scheduled: $PACKAGES"
	echo "============================================================================="
	echo
}

check_candidates() {
	PACKAGES=""
	TOTAL=0
	for PKG in $CANDIDATES ; do
		RESULT=$(sqlite3 -init $INIT ${PACKAGES_DB} "SELECT name from sources WHERE name = '$PKG';")
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
CANDIDATES="$@"
check_candidates
PACKAGES=$(echo $PACKAGES)
MESSAGE="$TOTAL package(s) blacklisted: ${PACKAGES}"
if [ $TOTAL -lt 1 ] ; then
	exit 1
fi

# finally
blacklist_packages
echo
echo "$MESSAGE"
kgb-client --conf /srv/jenkins/kgb/debian-reproducible.conf --relay-msg "$MESSAGE"
echo
echo "Probably edit notes.git/packages.yml now and enter reasons for blacklisting there"
