#!/bin/bash

# Copyright 2014 Holger Levsen <holger@layer-acht.org>
# released under the GPLv=2

. /srv/jenkins/bin/common-functions.sh
common_init "$@"

set +x

#
# define db
#
PACKAGES_DB=/var/lib/jenkins/reproducible.db
INIT=/var/lib/jenkins/reproducible.init
if [ ! -f $PACKAGES_DB ] ; then
	echo "$PACKAGES_DB doesn't exist, no builds possible."
	exit 1
elif [ -f $PACKAGES_DB.lock ] ; then
	for i in $(seq 0 100) ; do
		sleep 15
		[ -f $PACKAGES_DB.lock ] || break
	done
	echo "$PACKAGES_DB.lock still exist, exiting."
	exit 1
fi

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
}



#
# main
#
CANDIDATES="$@"
check_candidates
if [ $#{PACKAGES} -gt 256 ] ; then
	BLABLABLA="..."
fi
PACKAGES=$(echo $PACKAGES)
MESSAGE="$TOTAL package(s) manually (re-)scheduled: ${PACKAGES:0:256}$BLABLABLA"

# finally
schedule_packages
echo
echo "$MESSAGE"
kgb-client --conf /srv/jenkins/kgb/debian-reproducible.conf --relay-msg "$MESSAGE"
echo
