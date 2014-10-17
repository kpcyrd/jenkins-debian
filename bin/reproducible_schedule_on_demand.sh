#!/bin/bash

# Copyright 2014 Holger Levsen <holger@layer-acht.org>
# released under the GPLv=2

. /srv/jenkins/bin/common-functions.sh
common_init "$@"

# common code defining db access
. /srv/jenkins/bin/reproducible_common.sh

schedule_packages() {
	DATE="2014-10-01 00:23"
	TMPFILE=$(mktemp)
	for PKG in $PACKAGES ; do
		echo "REPLACE INTO sources_scheduled VALUES ('$PKG','$DATE','');" >> $TMPFILE
	done
	cat $TMPFILE | sqlite3 -init $INIT ${PACKAGES_DB}
	rm $TMPFILE
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
	if [ $TOTAL -eq 0 ] ; then
		echo "No packages to schedule, exiting."
		exit 0
	fi
}

#
# main
#
set +x
CANDIDATES="$@"
check_candidates
if [ ${#PACKAGES} -gt 256 ] ; then
	BLABLABLA="..."
fi
PACKAGES=$(echo $PACKAGES)
MESSAGE="$TOTAL package(s) manually (re-)scheduled for immediate testing: ${PACKAGES:0:256}$BLABLABLA"

# finally
schedule_packages
init_html
update_html_schedule
echo
echo "$MESSAGE"
kgb-client --conf /srv/jenkins/kgb/debian-reproducible.conf --relay-msg "$MESSAGE"
echo
