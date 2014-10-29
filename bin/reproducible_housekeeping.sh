#!/bin/bash

# Copyright 2014 Holger Levsen <holger@layer-acht.org>
# released under the GPLv=2

DEBUG=false
. /srv/jenkins/bin/common-functions.sh
common_init "$@"

# common code defining db access
. /srv/jenkins/bin/reproducible_common.sh

DIRTY=false

# prepare backup
REP_RESULTS=/srv/reproducible-results
mkdir -p $REP_RESULTS/backup
cd $REP_RESULTS/backup

# keep 30 days and the 1st of the month
DAY=(date -d "30 day ago" '+%d')
DATE=$(date -d "30 day ago" '+%Y-%m-%d')
if [ "$DAY" != "01" ] &&  [ -f reproducible_$DATE.db.xz ] ; then
	rm -f reproducible_$DATE.db.xz
fi

# actually do the backup
DATE=$(date '+%Y-%m-%d')
if [ ! -f reproducible_$DATE.db.xz ] ; then
	cp -v $PACKAGES_DB .
	DATE=$(date '+%Y-%m-%d')
	mv -v reproducible.db reproducible_$DATE.db
	xz reproducible_$DATE.db
fi

# find and warn about old temp directories
OLDSTUFF=$(find $REP_RESULTS -type d -name "tmp.*" -mtime +7 -exec ls -lad {} \;)
if [ ! -z "$OLDSTUFF" ] ; then
	echo
	echo "Warning: old temp directories found in $REP_RESULTS"
	echo "$OLDSTUFF"
	echo "Please cleanup manually."
	echo
	DIRTY=true
fi

# find and warn about pbuild leftovers
OLDSTUFF=$(find /var/cache/pbuilder/result/ -mtime +7 -exec ls -lad {} \;)
if [ ! -z "$OLDSTUFF" ] ; then
	echo
	echo "Warning: old files or directories found in /var/cache/pbuilder/result/"
	echo "$OLDSTUFF"
	echo "Please cleanup manually."
	echo
	DIRTY=true
fi

# find processes which should not be there
HAYSTACK=$(mktemp)
RESULT=$(mktemp)
ps axo pid,user,size,pcpu,cmd > $HAYSTACK
for ZOMBIE in $(pgrep -u 1234 -P 1 || true) ; do
	# faked-sysv comes and goes...
	grep ^$ZOMBIE $HAYSTACK | grep -v faked-sysv >> $RESULT 2> /dev/null
done
if [ -s $RESULT ] ; then
	echo
	echo "Warning: processes found which should not be there:"
	cat $RESULT
	echo
	echo "Please cleanup manually."
	echo
	DIRTY=true
fi
rm $HAYSTACK $RESULT

# find packages which build didnt end correctly
QUERY="
	SELECT * FROM sources_scheduled
		WHERE date_scheduled != ''
		AND date_build_started != ''
		AND date_build_started < datetime('now', '-1 day')
		ORDER BY date_scheduled
	"
PACKAGES=$(mktemp)
sqlite3 -init $INIT ${PACKAGES_DB} "$QUERY" > $PACKAGES 2> /dev/null || echo "Warning: SQL query '$QUERY' failed." 
if grep -q '|' $PACKAGES ; then
	echo
	echo "Warning: packages found where the build was started more than 24h ago:"
	echo "name|date_scheduled|date_build_started"
	echo
	cat $PACKAGES
	echo
	echo "To fix:"
	echo
	for PKG in $(cat $PACKAGES | cut -d "|" -f1) ; do
		echo "sqlite3 ${PACKAGES_DB}  \"DELETE FROM sources_scheduled WHERE name = '$PKG';\""
	done
	echo
	DIRTY=true
fi
rm $PACKAGES

if ! $DIRTY ; then
	echo "Everything seems to be fine."
	echo
fi
