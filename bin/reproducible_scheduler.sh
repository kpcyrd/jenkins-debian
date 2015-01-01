#!/bin/bash

# Copyright 2014 Holger Levsen <holger@layer-acht.org>
# released under the GPLv=2

DEBUG=false
. /srv/jenkins/bin/common-functions.sh
common_init "$@"

# common code defining db access
. /srv/jenkins/bin/reproducible_common.sh

#
# functions, see below for main
#
update_apt() {
	# this needs sid entries in sources.list:
	grep deb-src /etc/apt/sources.list | grep sid
	# try apt-get update three times, else fail
	sudo apt-get update || ( sleep $(( $RANDOM % 70 + 30 )) ; sudo apt-get update ) || ( sleep $(( $RANDOM % 70 + 30 )) ; sudo apt-get update || exit 1 ) 
}

cleanup_lock() {
	rm -f ${PACKAGES_DB}.lock
}

# update sources table in db
update_sources_table() {
	trap cleanup_lock INT TERM EXIT
	touch ${PACKAGES_DB}.lock
	TMPFILE=$(mktemp)
	curl $MIRROR/dists/sid/main/source/Sources.xz > $TMPFILE
	CSVFILE=$(mktemp)
	(xzcat $TMPFILE | egrep "(^Package:|^Version:)" | sed -s "s#^Version: ##g; s#Package: ##g; s#\n# #g"| while read PKG ; do read VERSION ; echo "$PKG,$VERSION" ; done) > $CSVFILE
	sqlite3 -csv -init $INIT ${PACKAGES_DB} "DELETE from sources"
	echo ".import $CSVFILE sources" | sqlite3 -csv -init $INIT ${PACKAGES_DB}
	# count unique packages for later comparison
	P_IN_TMPFILE=$(xzcat $TMPFILE | grep "^Package:" | cut -d " " -f2 | sort -u | wc -l)
	# cleanup files already
	rm $CSVFILE $TMPFILE
	# cleanup db
	echo "============================================================================="
	echo "$(date) Removing duplicate versions from sources db..."
	for PKG in $(sqlite3 ${PACKAGES_DB} 'SELECT name FROM sources GROUP BY name HAVING count(name) > 1') ; do
		BET=""
		for VERSION in $(sqlite3 ${PACKAGES_DB} "SELECT version FROM sources where name = \"$PKG\"") ; do
			if [ "$BET" = "" ] ; then
				BET=$VERSION
				continue
			elif dpkg --compare-versions "$BET" lt "$VERSION"  ; then
						BET=$VERSION
			fi
		done
		sqlite3 -init $INIT ${PACKAGES_DB} "DELETE FROM sources WHERE name = '$PKG' AND version != '$BET'"
	done
	echo "$(date) Done removing duplicate versions from sources db..."
	echo "============================================================================="
	cleanup_lock
	trap - INT TERM EXIT
	# verify duplicate entries have been removed correctly from the db
	P_IN_SOURCES=$(sqlite3 ${PACKAGES_DB} 'SELECT count(name) FROM sources')
	if [ $P_IN_TMPFILE -ne $P_IN_SOURCES ] ; then
		echo "DEBUG: P_IN_SOURCES = $P_IN_SOURCES"
		echo "DEBUG: P_IN_TMPFILE = $P_IN_TMPFILE"
		RESULT=1
	else
		RESULT=0
	fi
}

do_sql_query() {
	PACKAGES=$(sqlite3 -init $INIT ${PACKAGES_DB} "$QUERY")
	if [ ! -z "$PACKAGES" ] ; then
		AMOUNT=$(echo "$PACKAGES" | wc -l)
		PACKAGES="$(echo $PACKAGES)"
	else
		AMOUNT=0
	fi
	echo "Criteria: $1"
	echo "Amount:   $AMOUNT"
	echo "Packages: $PACKAGES"
	echo "============================================================================="
}

select_unknown_packages() {
	QUERY="
		SELECT DISTINCT sources.name FROM sources
			WHERE sources.name NOT IN
			(SELECT sources.name FROM sources,sources_scheduled
				WHERE sources.name=sources_scheduled.name)
			AND sources.name NOT IN
			(SELECT sources.name FROM sources,source_packages
				WHERE sources.name=source_packages.name)
			ORDER BY random()
		LIMIT $1"
	do_sql_query "not tested before, randomly sorted"
}

select_new_versions() {
	QUERY="
		SELECT DISTINCT sources.name FROM sources,source_packages
			WHERE sources.name NOT IN
			(SELECT sources.name FROM sources,sources_scheduled
				WHERE sources.name=sources_scheduled.name)
			AND sources.name IN
			(SELECT sources.name FROM sources,source_packages
				WHERE sources.name=source_packages.name
				AND sources.version!=source_packages.version
				AND source_packages.status!='blacklisted')
			AND sources.name=source_packages.name
			ORDER BY source_packages.build_date
		LIMIT $1"
	do_sql_query "tested before, new version available, sorted by last test date"
}

select_old_versions() {
	# old versions older than two weeks only
	QUERY="
		SELECT DISTINCT sources.name FROM sources,source_packages
			WHERE sources.name NOT IN
			(SELECT sources.name FROM sources,sources_scheduled
				WHERE sources.name=sources_scheduled.name)
			AND sources.name IN
			(SELECT sources.name FROM sources,source_packages
				WHERE sources.name=source_packages.name
				AND sources.version=source_packages.version
				AND source_packages.status!='blacklisted')
			AND sources.name=source_packages.name
			AND source_packages.build_date < datetime('now', '-14 day')
			ORDER BY source_packages.build_date
		LIMIT $1"
	do_sql_query "tested at least two weeks ago, no new version available, sorted by last test date"
}


schedule_packages() {
	DATE=$(date +'%Y-%m-%d %H:%M')
	TMPFILE=$(mktemp)
	for PKG in $ALL_PACKAGES ; do
		echo "INSERT INTO sources_scheduled VALUES ('$PKG','$DATE','');" >> $TMPFILE
	done
	cat $TMPFILE | sqlite3 -init $INIT ${PACKAGES_DB}
	rm $TMPFILE
	echo "============================================================================="
	echo "The following $TOTAL source packages have been scheduled: $ALL_PACKAGES"
	echo "============================================================================="
	echo
}

deselect_old_with_buildinfo() {
	PACKAGES=""
	for PKG in $1 do ;
		if [ ! -f /var/lib/jenkins/userContent/buildinfo/${PKG}_.buildinfo ] ; then
			PACKAGES="$PACKAGES $PKG"
		else
			let "AMOUNT=$AMOUNT-1"
		fi
	done
}

#
# main
#
set +x
update_apt
init_html
COUNT_SCHEDULED=$(sqlite3 ${PACKAGES_DB} 'SELECT count(name) FROM sources_scheduled')
if [ $COUNT_SCHEDULED -gt 250 ] ; then
	update_html_schedule
	echo "$COUNT_SCHEDULED packages scheduled, nothing to do."
	exit 0
else
	echo "$COUNT_SCHEDULED packages currently scheduled, scheduling some more..."
fi

RESULT=0
for i in 1 2 3 4 5 ; do
	# try fives times, before failing the job
	update_sources_table
	if [ $RESULT -eq 0 ] ; then
		break
	fi
	sleep 2m
done
if [ $RESULT -ne 0 ] ; then
	echo "failure to update sources table"
	exit 1
fi

echo "Requesting 200 unknown packages..."
select_unknown_packages 200
let "TOTAL=$COUNT_SCHEDULED+$AMOUNT"
echo "So in total now $TOTAL packages about to be scheduled."
ALL_PACKAGES="$PACKAGES"
MESSAGE="Scheduled $AMOUNT unknown packages"

if [ $TOTAL -le 250 ] ; then
	NEW=50
elif [ $TOTAL -le 450 ] ; then
	NEW=25
fi
echo "Requesting $NEW new versions..."
select_new_versions $NEW
let "TOTAL=$TOTAL+$AMOUNT"
echo "So in total now $TOTAL packages about to be scheduled."
ALL_PACKAGES="$ALL_PACKAGES $PACKAGES"
MESSAGE="$MESSAGE, $AMOUNT packages with new versions"

if [ $TOTAL -lt 250 ] ; then
	OLD=200
elif [ $TOTAL -le 350 ] ; then
	OLD=100
else
	OLD=1
fi
echo "Requesting $OLD old packages..."
select_old_versions $OLD
echo -n "Found $AMOUNT old packages, "
deselect_old_with_buildinfo $PACKAGES
echo "kept $AMOUNT old packages without .buildinfo files."

let "TOTAL=$TOTAL+$AMOUNT"
echo "So in total now $TOTAL packages about to be scheduled."
ALL_PACKAGES="$ALL_PACKAGES $PACKAGES"
MESSAGE="$MESSAGE and $AMOUNT packages with the same version (but without .buildinfo files) again, for a total of $TOTAL scheduled packages."

# finally
schedule_packages
update_html_schedule
echo
echo "$MESSAGE"
kgb-client --conf /srv/jenkins/kgb/debian-reproducible.conf --relay-msg "$MESSAGE"
echo
